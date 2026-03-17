"""
Tests for Glue Redshift Crawler sample.

Run all IaC methods:
    uv run pytest samples/glue-redshift-crawler/python/ -v

Run specific IaC method:
    uv run pytest samples/glue-redshift-crawler/python/ -v -k scripts
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from conftest import (
    AWSClients,
    WaitFor,
    run_deploy,
    get_sample_dir,
)

SAMPLE_NAME = "glue-redshift-crawler"
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

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method, timeout=600)
    env["_IAC_METHOD"] = iac_method

    return env


class TestGlueRedshiftCrawler:
    """Test Redshift cluster, Glue database, connection, crawler, and catalog table."""

    def test_redshift_cluster_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the Redshift cluster was created."""
        cluster_id = deployed_env.get("REDSHIFT_CLUSTER_ID")
        assert cluster_id, "REDSHIFT_CLUSTER_ID should be set"

        response = aws_clients.redshift_client.describe_clusters(
            ClusterIdentifier=cluster_id
        )
        assert len(response["Clusters"]) == 1

    def test_redshift_cluster_available(self, deployed_env, aws_clients: AWSClients):
        """Test that the Redshift cluster is available."""
        cluster_id = deployed_env.get("REDSHIFT_CLUSTER_ID")

        response = aws_clients.redshift_client.describe_clusters(
            ClusterIdentifier=cluster_id
        )
        assert response["Clusters"][0]["ClusterStatus"] == "available"

    def test_glue_database_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the Glue catalog database was created."""
        glue_db = deployed_env.get("GLUE_DB_NAME")
        assert glue_db, "GLUE_DB_NAME should be set"

        response = aws_clients.glue_client.get_database(Name=glue_db)
        assert response["Database"]["Name"] == glue_db

    def test_glue_connection_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the Glue JDBC connection was created."""
        conn_name = deployed_env.get("GLUE_CONNECTION_NAME")
        assert conn_name, "GLUE_CONNECTION_NAME should be set"

        response = aws_clients.glue_client.get_connection(Name=conn_name)
        assert response["Connection"]["ConnectionType"] == "JDBC"

    def test_glue_connection_has_jdbc_url(self, deployed_env, aws_clients: AWSClients):
        """Test that the connection has a JDBC URL pointing to Redshift."""
        conn_name = deployed_env.get("GLUE_CONNECTION_NAME")

        response = aws_clients.glue_client.get_connection(Name=conn_name)
        jdbc_url = response["Connection"]["ConnectionProperties"].get("JDBC_CONNECTION_URL", "")
        assert "jdbc:redshift://" in jdbc_url

    def test_glue_crawler_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the Glue crawler was created."""
        crawler_name = deployed_env.get("GLUE_CRAWLER_NAME")
        assert crawler_name, "GLUE_CRAWLER_NAME should be set"

        response = aws_clients.glue_client.get_crawler(Name=crawler_name)
        assert response["Crawler"]["Name"] == crawler_name

    def test_glue_crawler_is_ready(self, deployed_env, aws_clients: AWSClients):
        """Test that the crawler has finished running."""
        crawler_name = deployed_env.get("GLUE_CRAWLER_NAME")

        response = aws_clients.glue_client.get_crawler(Name=crawler_name)
        assert response["Crawler"]["State"] == "READY"

    def test_glue_crawler_targets_redshift(self, deployed_env, aws_clients: AWSClients):
        """Test that the crawler targets the Redshift table via JDBC."""
        crawler_name = deployed_env.get("GLUE_CRAWLER_NAME")

        response = aws_clients.glue_client.get_crawler(Name=crawler_name)
        jdbc_targets = response["Crawler"]["Targets"].get("JdbcTargets", [])
        assert len(jdbc_targets) >= 1
        assert "sales" in jdbc_targets[0].get("Path", "")

    def test_glue_table_created_by_crawler(self, deployed_env, aws_clients: AWSClients):
        """Test that the crawler populated the Glue catalog with the Redshift table."""
        glue_db = deployed_env.get("GLUE_DB_NAME")
        glue_table = deployed_env.get("GLUE_TABLE_NAME")
        assert glue_table, "GLUE_TABLE_NAME should be set"

        response = aws_clients.glue_client.get_table(
            DatabaseName=glue_db, Name=glue_table
        )
        assert response["Table"]["Name"] == glue_table

    def test_glue_table_has_columns(self, deployed_env, aws_clients: AWSClients):
        """Test that the crawled table has the expected column schema."""
        glue_db = deployed_env.get("GLUE_DB_NAME")
        glue_table = deployed_env.get("GLUE_TABLE_NAME")

        response = aws_clients.glue_client.get_table(
            DatabaseName=glue_db, Name=glue_table
        )
        columns = response["Table"]["StorageDescriptor"]["Columns"]
        column_names = [c["Name"] for c in columns]

        # The sales table should have these columns from the CREATE TABLE
        assert "salesid" in column_names
        assert "listid" in column_names
        assert "pricepaid" in column_names
