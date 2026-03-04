"""
Tests for web-app-rds sample.

Run with:
    uv run pytest samples/web-app-rds/python/ -v
"""

import json
from pathlib import Path

import pytest

# Sample configuration
SAMPLE_NAME = "web-app-rds"
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


class TestWebAppRds:
    """Test suite for Web App RDS sample."""

    def test_function_exists(self, deployed_env, aws_clients):
        """Lambda function should exist and be active."""
        function_name = deployed_env["FUNCTION_NAME"]
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_health_check(self, deployed_env, invoke_lambda):
        """Health check should pass."""
        function_name = deployed_env["FUNCTION_NAME"]

        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/health"
        })

        assert response["statusCode"] == 200

    def test_create_item(self, deployed_env, invoke_lambda):
        """Should create an item."""
        function_name = deployed_env["FUNCTION_NAME"]

        response = invoke_lambda(function_name, {
            "httpMethod": "POST",
            "path": "/items",
            "body": json.dumps({
                "id": "rds-001",
                "name": "Database Product",
                "category": "software",
                "price": 199.99
            })
        })

        assert response["statusCode"] == 201
        body = json.loads(response["body"])
        assert body["id"] == "rds-001"

    def test_get_item(self, deployed_env, invoke_lambda):
        """Should get an item by ID."""
        function_name = deployed_env["FUNCTION_NAME"]

        # Create item
        invoke_lambda(function_name, {
            "httpMethod": "POST",
            "path": "/items",
            "body": json.dumps({
                "id": "rds-002",
                "name": "Another Product"
            })
        })

        # Get item
        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/items/rds-002",
            "pathParameters": {"id": "rds-002"}
        })

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["name"] == "Another Product"

    def test_update_item(self, deployed_env, invoke_lambda):
        """Should update an existing item."""
        function_name = deployed_env["FUNCTION_NAME"]

        # Create item
        invoke_lambda(function_name, {
            "httpMethod": "POST",
            "path": "/items",
            "body": json.dumps({
                "id": "rds-003",
                "name": "Original Name"
            })
        })

        # Update item
        response = invoke_lambda(function_name, {
            "httpMethod": "PUT",
            "path": "/items/rds-003",
            "pathParameters": {"id": "rds-003"},
            "body": json.dumps({
                "name": "Updated Name",
                "price": 249.99
            })
        })

        assert response["statusCode"] == 200

    def test_list_items(self, deployed_env, invoke_lambda):
        """Should list all items."""
        function_name = deployed_env["FUNCTION_NAME"]

        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/items"
        })

        assert response["statusCode"] == 200

    def test_delete_item(self, deployed_env, invoke_lambda):
        """Should delete an item."""
        function_name = deployed_env["FUNCTION_NAME"]

        # Create item
        invoke_lambda(function_name, {
            "httpMethod": "POST",
            "path": "/items",
            "body": json.dumps({
                "id": "rds-delete",
                "name": "To Be Deleted"
            })
        })

        # Delete item
        response = invoke_lambda(function_name, {
            "httpMethod": "DELETE",
            "path": "/items/rds-delete",
            "pathParameters": {"id": "rds-delete"}
        })

        assert response["statusCode"] == 204
