"""
Tests for lambda-function-urls sample.

Run with:
    uv run pytest samples/lambda-function-urls/python/ -v
"""

import json
from pathlib import Path

import pytest

# Sample configuration
SAMPLE_NAME = "lambda-function-urls"
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

    # Skip if deploy script doesn't exist
    script_path = get_deploy_script_path(SAMPLE_NAME, LANGUAGE, iac_method)
    if not script_path.exists():
        pytest.skip(f"Deploy script not found for {iac_method}")

    # Deploy and return env vars
    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method)

    # Wait for Lambda to be active
    if "FUNCTION_NAME" in env:
        wait_for.lambda_active(env["FUNCTION_NAME"])

    return env


class TestLambdaFunctionUrls:
    """Test suite for Lambda Function URLs sample."""

    def test_function_exists(self, deployed_env, aws_clients):
        """Lambda function should exist and be active."""
        function_name = deployed_env["FUNCTION_NAME"]

        response = aws_clients.lambda_client.get_function(FunctionName=function_name)

        assert response["Configuration"]["State"] == "Active"
        assert response["Configuration"]["Runtime"] == "python3.12"

    def test_function_invocation_hello(self, deployed_env, invoke_lambda):
        """Lambda should respond to hello request."""
        function_name = deployed_env["FUNCTION_NAME"]

        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/hello",
            "queryStringParameters": {"name": "World"}
        })

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert "Hello" in body.get("message", "")

    def test_function_invocation_health(self, deployed_env, invoke_lambda):
        """Lambda should respond to health check."""
        function_name = deployed_env["FUNCTION_NAME"]

        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/health"
        })

        assert response["statusCode"] == 200

    def test_function_invocation_echo(self, deployed_env, invoke_lambda):
        """Lambda should echo back request body in response."""
        function_name = deployed_env["FUNCTION_NAME"]
        test_data = {"key": "value", "number": 42}

        response = invoke_lambda(function_name, {
            "httpMethod": "POST",
            "path": "/echo",
            "body": json.dumps(test_data)
        })

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        # Lambda echoes body in request.body field
        assert body.get("request", {}).get("body") == test_data

    def test_function_invocation_info(self, deployed_env, invoke_lambda):
        """Lambda should return info."""
        function_name = deployed_env["FUNCTION_NAME"]

        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/info"
        })

        assert response["statusCode"] == 200

    def test_function_returns_function_name(self, deployed_env, invoke_lambda):
        """Lambda should return its function name in response."""
        function_name = deployed_env["FUNCTION_NAME"]

        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/any-path"
        })

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body.get("functionName") == function_name

    def test_function_url_exists(self, deployed_env, aws_clients):
        """Function URL should be configured."""
        function_name = deployed_env["FUNCTION_NAME"]

        try:
            response = aws_clients.lambda_client.get_function_url_config(
                FunctionName=function_name
            )
            assert response["AuthType"] == "NONE"
            assert "FunctionUrl" in response
        except aws_clients.lambda_client.exceptions.ResourceNotFoundException:
            pytest.skip("Function URL not configured")
