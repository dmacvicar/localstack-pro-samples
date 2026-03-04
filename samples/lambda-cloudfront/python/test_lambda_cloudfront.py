"""
Tests for lambda-cloudfront sample.

Run with:
    uv run pytest samples/lambda-cloudfront/python/ -v
"""

import json
from pathlib import Path

import pytest

# Sample configuration
SAMPLE_NAME = "lambda-cloudfront"
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


class TestLambdaCloudFront:
    """Test suite for Lambda CloudFront sample."""

    def test_function_exists(self, deployed_env, aws_clients):
        """Lambda function should exist and be active."""
        function_name = deployed_env["FUNCTION_NAME"]
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_function_invocation(self, deployed_env, invoke_lambda):
        """Lambda should respond to invocation."""
        function_name = deployed_env["FUNCTION_NAME"]

        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/test"
        })

        assert response["statusCode"] == 200

    def test_function_url_exists(self, deployed_env, aws_clients):
        """Function URL should be configured (if available)."""
        function_name = deployed_env["FUNCTION_NAME"]

        try:
            response = aws_clients.lambda_client.get_function_url_config(
                FunctionName=function_name
            )
            assert "FunctionUrl" in response
        except aws_clients.lambda_client.exceptions.ResourceNotFoundException:
            pytest.skip("Function URL not configured for this deployment")

    def test_cloudfront_distribution_exists(self, deployed_env, aws_clients):
        """CloudFront distribution should exist (if configured)."""
        distribution_id = deployed_env.get("DISTRIBUTION_ID")
        if not distribution_id:
            pytest.skip("CloudFront distribution not configured")

        response = aws_clients.cloudfront_client.get_distribution(
            Id=distribution_id
        )
        assert response["Distribution"]["Status"] in ["Deployed", "InProgress"]
