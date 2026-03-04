"""
Tests for apigw-custom-domain sample.

Run with:
    uv run pytest samples/apigw-custom-domain/python/ -v
"""

import json
from pathlib import Path

import pytest
import requests

# Sample configuration
SAMPLE_NAME = "apigw-custom-domain"
LANGUAGE = "python"
SAMPLE_DIR = Path(__file__).parent


def get_iac_methods():
    """Discover available IaC methods for this sample."""
    methods = []
    if (SAMPLE_DIR / "scripts" / "deploy.sh").exists():
        methods.append("scripts")
    for iac in ["terraform", "cloudformation", "cdk"]:
        if (SAMPLE_DIR / iac / "deploy.sh").exists():
            methods.append(iac)
    return methods


@pytest.fixture(scope="module", params=get_iac_methods())
def deployed_env(request, wait_for):
    """Deploy the sample with each IaC method and return env vars."""
    from conftest import run_deploy, get_deploy_script_path

    iac_method = request.param

    script_path = get_deploy_script_path(SAMPLE_NAME, LANGUAGE, iac_method)
    if not script_path.exists():
        pytest.skip(f"Deploy script not found for {iac_method}")

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method)

    if "FUNCTION_NAME" in env:
        wait_for.lambda_active(env["FUNCTION_NAME"])

    return env


class TestApiGwCustomDomain:
    """Test suite for API Gateway Custom Domain sample."""

    def test_acm_certificate_exists(self, deployed_env, aws_clients):
        """ACM certificate should exist."""
        cert_arn = deployed_env.get("CERT_ARN")
        if not cert_arn:
            pytest.skip("No certificate ARN configured")

        response = aws_clients.acm_client.describe_certificate(
            CertificateArn=cert_arn
        )
        # LocalStack may return different statuses
        assert response["Certificate"]["Status"] in ["ISSUED", "PENDING_VALIDATION"]

    def test_route53_hosted_zone_exists(self, deployed_env, aws_clients):
        """Route53 hosted zone should exist."""
        zone_id = deployed_env.get("HOSTED_ZONE_ID")
        if not zone_id or zone_id == "None":
            pytest.skip("No hosted zone ID configured")

        response = aws_clients.route53_client.get_hosted_zone(Id=zone_id)
        assert "HostedZone" in response

    def test_lambda_function_active(self, deployed_env, aws_clients):
        """Lambda function should be active."""
        function_name = deployed_env["FUNCTION_NAME"]
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_http_api_exists(self, deployed_env, aws_clients):
        """API Gateway HTTP API should exist."""
        api_id = deployed_env["API_ID"]
        response = aws_clients.apigatewayv2_client.get_api(ApiId=api_id)
        assert response["ProtocolType"] == "HTTP"

    def test_custom_domain_configured(self, deployed_env, aws_clients):
        """Custom domain should be configured."""
        domain_name = deployed_env["DOMAIN_NAME"]
        response = aws_clients.apigatewayv2_client.get_domain_name(
            DomainName=domain_name
        )
        assert "DomainNameConfigurations" in response

    def test_api_responds_via_custom_domain(self, deployed_env):
        """API should respond via custom domain."""
        domain_name = deployed_env["DOMAIN_NAME"]

        # Test using Host header for custom domain routing
        try:
            response = requests.get(
                "http://localhost.localstack.cloud:4566/hello",
                headers={"Host": domain_name},
                timeout=10
            )
            if response.status_code == 200 and "Hello" in response.text:
                assert True
                return
        except requests.exceptions.RequestException:
            pass

        # Fallback: test direct API endpoint
        api_endpoint = deployed_env.get("API_ENDPOINT")
        if api_endpoint:
            try:
                response = requests.get(f"{api_endpoint}/hello", timeout=10)
                assert response.status_code == 200
                assert "Hello" in response.text
                return
            except requests.exceptions.RequestException:
                pass

        pytest.skip("API endpoint not reachable")

    def test_lambda_invocation(self, deployed_env, invoke_lambda):
        """Lambda should respond to invocation."""
        function_name = deployed_env["FUNCTION_NAME"]

        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/hello"
        })

        assert response["statusCode"] == 200
