"""
Tests for web-app-dynamodb sample.

Run with:
    uv run pytest samples/web-app-dynamodb/python/ -v
"""

import json
from pathlib import Path

import pytest

# Sample configuration
SAMPLE_NAME = "web-app-dynamodb"
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


class TestWebAppDynamoDB:
    """Test suite for Web App DynamoDB sample."""

    def test_function_exists(self, deployed_env, aws_clients):
        """Lambda function should exist and be active."""
        function_name = deployed_env["FUNCTION_NAME"]
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_table_exists(self, deployed_env, aws_clients):
        """DynamoDB table should exist."""
        table_name = deployed_env["TABLE_NAME"]
        response = aws_clients.dynamodb_client.describe_table(TableName=table_name)
        assert response["Table"]["TableStatus"] == "ACTIVE"

    def test_create_item(self, deployed_env, invoke_lambda):
        """Should create an item."""
        function_name = deployed_env["FUNCTION_NAME"]

        response = invoke_lambda(function_name, {
            "httpMethod": "POST",
            "path": "/items",
            "body": json.dumps({
                "id": "test-001",
                "name": "Test Product",
                "category": "electronics",
                "price": 99.99
            })
        })

        assert response["statusCode"] == 201
        body = json.loads(response["body"])
        assert body["id"] == "test-001"

    def test_get_item(self, deployed_env, invoke_lambda):
        """Should get an item by ID."""
        function_name = deployed_env["FUNCTION_NAME"]

        # First create the item
        invoke_lambda(function_name, {
            "httpMethod": "POST",
            "path": "/items",
            "body": json.dumps({
                "id": "test-002",
                "name": "Another Product"
            })
        })

        # Then get it
        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/items/test-002",
            "pathParameters": {"id": "test-002"}
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
                "id": "test-003",
                "name": "Original Name"
            })
        })

        # Update item
        response = invoke_lambda(function_name, {
            "httpMethod": "PUT",
            "path": "/items/test-003",
            "pathParameters": {"id": "test-003"},
            "body": json.dumps({
                "name": "Updated Name",
                "price": 149.99
            })
        })

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["name"] == "Updated Name"

    def test_list_items(self, deployed_env, invoke_lambda):
        """Should list all items."""
        function_name = deployed_env["FUNCTION_NAME"]

        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/items"
        })

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert "items" in body
        assert isinstance(body["items"], list)

    def test_delete_item(self, deployed_env, invoke_lambda):
        """Should delete an item."""
        function_name = deployed_env["FUNCTION_NAME"]

        # Create item
        invoke_lambda(function_name, {
            "httpMethod": "POST",
            "path": "/items",
            "body": json.dumps({
                "id": "test-delete",
                "name": "To Be Deleted"
            })
        })

        # Delete item
        response = invoke_lambda(function_name, {
            "httpMethod": "DELETE",
            "path": "/items/test-delete",
            "pathParameters": {"id": "test-delete"}
        })

        assert response["statusCode"] == 204

    def test_get_deleted_item_returns_404(self, deployed_env, invoke_lambda):
        """Should return 404 for deleted item."""
        function_name = deployed_env["FUNCTION_NAME"]

        # Create and delete item
        invoke_lambda(function_name, {
            "httpMethod": "POST",
            "path": "/items",
            "body": json.dumps({
                "id": "test-gone",
                "name": "Will Be Gone"
            })
        })
        invoke_lambda(function_name, {
            "httpMethod": "DELETE",
            "path": "/items/test-gone",
            "pathParameters": {"id": "test-gone"}
        })

        # Try to get deleted item
        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/items/test-gone",
            "pathParameters": {"id": "test-gone"}
        })

        assert response["statusCode"] == 404
