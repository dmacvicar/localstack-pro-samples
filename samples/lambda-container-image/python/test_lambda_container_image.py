"""
Tests for lambda-container-image sample.

Run with:
    uv run pytest samples/lambda-container-image/python/ -v
"""

import json
from pathlib import Path

import pytest

# Sample configuration
SAMPLE_NAME = "lambda-container-image"
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


class TestLambdaContainerImage:
    """Test suite for Lambda Container Image sample."""

    def test_ecr_repository_exists(self, deployed_env, aws_clients):
        """ECR repository should exist."""
        repo_name = deployed_env["REPO_NAME"]
        response = aws_clients.ecr_client.describe_repositories(
            repositoryNames=[repo_name]
        )
        assert len(response["repositories"]) == 1
        assert response["repositories"][0]["repositoryName"] == repo_name

    def test_image_in_ecr(self, deployed_env, aws_clients):
        """Docker image should be in ECR."""
        repo_name = deployed_env["REPO_NAME"]
        response = aws_clients.ecr_client.list_images(repositoryName=repo_name)
        image_ids = response.get("imageIds", [])
        assert len(image_ids) > 0, "No images in repository"

        # Check for latest tag
        tags = [img.get("imageTag") for img in image_ids if img.get("imageTag")]
        assert "latest" in tags, "No 'latest' tag found"

    def test_function_exists(self, deployed_env, aws_clients):
        """Lambda function should exist and be active."""
        function_name = deployed_env["FUNCTION_NAME"]
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_function_is_container_image(self, deployed_env, aws_clients):
        """Lambda should be a container image type."""
        function_name = deployed_env["FUNCTION_NAME"]
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["PackageType"] == "Image"

    def test_function_invocation(self, deployed_env, invoke_lambda):
        """Lambda should invoke successfully."""
        function_name = deployed_env["FUNCTION_NAME"]
        response = invoke_lambda(function_name, {"test": "data"})
        assert response.get("statusCode") == 200

    def test_function_returns_event(self, deployed_env, invoke_lambda):
        """Lambda should return the event in response."""
        function_name = deployed_env["FUNCTION_NAME"]
        test_event = {"key1": "value1", "key2": "value2"}
        response = invoke_lambda(function_name, test_event)

        body = response.get("body")
        if isinstance(body, str):
            body = json.loads(body)

        assert body.get("message") == "Hello from Lambda container image!"
        assert body.get("event") == test_event
