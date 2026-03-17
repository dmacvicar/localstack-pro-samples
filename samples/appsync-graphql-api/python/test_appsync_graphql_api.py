"""
Tests for AppSync GraphQL API sample.

Run all IaC methods:
    uv run pytest samples/appsync-graphql-api/python/ -v

Run specific IaC method:
    uv run pytest samples/appsync-graphql-api/python/ -v -k scripts

Note: First run may take time to download PostgreSQL Docker image for RDS.
"""

import json
import sys
from pathlib import Path

import pytest
import requests

# Add samples directory to path for conftest imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from conftest import (
    AWSClients,
    WaitFor,
    run_deploy,
    get_sample_dir,
    LOCALSTACK_ENDPOINT,
)

SAMPLE_NAME = "appsync-graphql-api"
LANGUAGE = "python"

IAC_METHODS = ["scripts", "terraform", "cloudformation", "cdk"]


@pytest.fixture(scope="module", params=IAC_METHODS)
def deployed_env(request, aws_clients: AWSClients, wait_for: WaitFor):
    """Deploy the sample and return environment variables."""
    iac_method = request.param

    sample_dir = get_sample_dir(SAMPLE_NAME, LANGUAGE)
    if iac_method == "scripts":
        deploy_path = sample_dir / "scripts" / "deploy.sh"
    else:
        deploy_path = sample_dir / iac_method / "deploy.sh"

    if not deploy_path.exists():
        pytest.skip(f"Deploy script not found: {deploy_path}")

    # Longer timeout for RDS Aurora cluster creation
    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method, timeout=600)
    env["_IAC_METHOD"] = iac_method

    return env


def graphql_query(api_url, api_key, query):
    """Execute a GraphQL query against the AppSync endpoint."""
    response = requests.post(
        api_url,
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
        },
        json={"query": query},
        timeout=30,
    )
    return response


class TestAppSyncGraphQLApi:
    """Test AppSync GraphQL API resources."""

    def test_api_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the AppSync API was created."""
        api_id = deployed_env.get("API_ID")
        assert api_id, "API_ID should be set"

        response = aws_clients.appsync_client.get_graphql_api(apiId=api_id)
        assert response["graphqlApi"]["apiId"] == api_id

    def test_api_auth_type(self, deployed_env, aws_clients: AWSClients):
        """Test that the API uses API_KEY authentication."""
        api_id = deployed_env.get("API_ID")

        response = aws_clients.appsync_client.get_graphql_api(apiId=api_id)
        assert response["graphqlApi"]["authenticationType"] == "API_KEY"

    def test_api_key_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that an API key was created."""
        api_id = deployed_env.get("API_ID")
        api_key = deployed_env.get("API_KEY")
        assert api_key, "API_KEY should be set"

        response = aws_clients.appsync_client.list_api_keys(apiId=api_id)
        key_ids = [k["id"] for k in response["apiKeys"]]
        assert api_key in key_ids

    def test_dynamodb_table_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the DynamoDB table was created."""
        table_name = deployed_env.get("TABLE_NAME")
        assert table_name, "TABLE_NAME should be set"

        response = aws_clients.dynamodb_client.describe_table(TableName=table_name)
        assert response["Table"]["TableName"] == table_name

    def test_rds_cluster_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the RDS Aurora cluster was created."""
        db_cluster_id = deployed_env.get("DB_CLUSTER_ID")
        assert db_cluster_id, "DB_CLUSTER_ID should be set"

        response = aws_clients.rds_client.describe_db_clusters(
            DBClusterIdentifier=db_cluster_id
        )
        assert len(response["DBClusters"]) == 1

    def test_ddb_data_source_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the DynamoDB data source was created."""
        api_id = deployed_env.get("API_ID")

        response = aws_clients.appsync_client.get_data_source(
            apiId=api_id, name="ds_ddb"
        )
        assert response["dataSource"]["type"] == "AMAZON_DYNAMODB"

    def test_rds_data_source_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the RDS data source was created."""
        api_id = deployed_env.get("API_ID")

        response = aws_clients.appsync_client.get_data_source(
            apiId=api_id, name="ds_rds"
        )
        assert response["dataSource"]["type"] == "RELATIONAL_DATABASE"

    def test_ddb_resolvers_exist(self, deployed_env, aws_clients: AWSClients):
        """Test that DynamoDB resolvers were created."""
        api_id = deployed_env.get("API_ID")

        # Check mutation resolver
        response = aws_clients.appsync_client.get_resolver(
            apiId=api_id, typeName="Mutation", fieldName="addPostDDB"
        )
        assert response["resolver"]["dataSourceName"] == "ds_ddb"

        # Check query resolver
        response = aws_clients.appsync_client.get_resolver(
            apiId=api_id, typeName="Query", fieldName="getPostsDDB"
        )
        assert response["resolver"]["dataSourceName"] == "ds_ddb"

    def test_rds_resolvers_exist(self, deployed_env, aws_clients: AWSClients):
        """Test that RDS resolvers were created."""
        api_id = deployed_env.get("API_ID")

        # Check mutation resolver
        response = aws_clients.appsync_client.get_resolver(
            apiId=api_id, typeName="Mutation", fieldName="addPostRDS"
        )
        assert response["resolver"]["dataSourceName"] == "ds_rds"

        # Check query resolver
        response = aws_clients.appsync_client.get_resolver(
            apiId=api_id, typeName="Query", fieldName="getPostsRDS"
        )
        assert response["resolver"]["dataSourceName"] == "ds_rds"

    def test_graphql_ddb_mutation(self, deployed_env):
        """Test DynamoDB mutation via GraphQL endpoint."""
        api_url = deployed_env.get("API_URL")
        api_key = deployed_env.get("API_KEY")
        assert api_url, "API_URL should be set"

        response = graphql_query(
            api_url, api_key,
            'mutation { addPostDDB(id: "test-id-1") { id } }'
        )
        assert response.status_code == 200
        data = response.json()
        assert "data" in data
        assert "addPostDDB" in data["data"]

    def test_graphql_ddb_query(self, deployed_env):
        """Test DynamoDB query via GraphQL endpoint."""
        api_url = deployed_env.get("API_URL")
        api_key = deployed_env.get("API_KEY")

        # First insert
        graphql_query(
            api_url, api_key,
            'mutation { addPostDDB(id: "test-id-2") { id } }'
        )

        # Then query
        response = graphql_query(
            api_url, api_key,
            "query { getPostsDDB { id } }"
        )
        assert response.status_code == 200
        data = response.json()
        assert "data" in data
        assert "getPostsDDB" in data["data"]
        # Should have at least one post
        posts = data["data"]["getPostsDDB"]
        assert len(posts) >= 1

    def test_graphql_rds_mutation(self, deployed_env):
        """Test RDS mutation via GraphQL endpoint."""
        api_url = deployed_env.get("API_URL")
        api_key = deployed_env.get("API_KEY")

        response = graphql_query(
            api_url, api_key,
            'mutation { addPostRDS(id: "rds-id-1") { id } }'
        )
        assert response.status_code == 200
        data = response.json()
        assert "data" in data
        assert "addPostRDS" in data["data"]

    def test_graphql_rds_query(self, deployed_env):
        """Test RDS query via GraphQL endpoint."""
        api_url = deployed_env.get("API_URL")
        api_key = deployed_env.get("API_KEY")

        # First insert
        graphql_query(
            api_url, api_key,
            'mutation { addPostRDS(id: "rds-id-2") { id } }'
        )

        # Then query
        response = graphql_query(
            api_url, api_key,
            "query { getPostsRDS { id } }"
        )
        assert response.status_code == 200
        data = response.json()
        assert "data" in data
        assert "getPostsRDS" in data["data"]
        posts = data["data"]["getPostsRDS"]
        assert len(posts) >= 1
