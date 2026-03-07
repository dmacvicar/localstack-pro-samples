"""
Tests for Glacier and S3 Select sample.

Run all IaC methods:
    uv run pytest samples/glacier-s3-select/python/ -v

Run specific IaC method:
    uv run pytest samples/glacier-s3-select/python/ -v -k scripts
    uv run pytest samples/glacier-s3-select/python/ -v -k terraform
"""

import sys
import time
from pathlib import Path

import pytest

# Add samples directory to path for conftest imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from conftest import (
    AWSClients,
    WaitFor,
    run_deploy,
    get_sample_dir,
)

SAMPLE_NAME = "glacier-s3-select"
LANGUAGE = "python"

# IaC methods to test
IAC_METHODS = ["scripts", "terraform", "cloudformation", "cdk"]


@pytest.fixture(scope="module", params=IAC_METHODS)
def deployed_env(request, aws_clients: AWSClients, wait_for: WaitFor):
    """Deploy the sample and return environment variables."""
    iac_method = request.param

    # Check if deploy script exists
    sample_dir = get_sample_dir(SAMPLE_NAME, LANGUAGE)
    if iac_method == "scripts":
        deploy_path = sample_dir / "scripts" / "deploy.sh"
    else:
        deploy_path = sample_dir / iac_method / "deploy.sh"

    if not deploy_path.exists():
        pytest.skip(f"Deploy script not found: {deploy_path}")

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method, timeout=180)

    # Add IaC method to env for test identification
    env["_IAC_METHOD"] = iac_method

    return env


class TestGlacierS3Select:
    """Test Glacier vault and S3 Select functionality."""

    def test_bucket_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the S3 bucket was created."""
        bucket_name = deployed_env.get("BUCKET_NAME")
        assert bucket_name, "BUCKET_NAME should be set"

        response = aws_clients.s3_client.head_bucket(Bucket=bucket_name)
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    def test_results_bucket_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the results bucket was created."""
        results_bucket = deployed_env.get("RESULTS_BUCKET")
        assert results_bucket, "RESULTS_BUCKET should be set"

        response = aws_clients.s3_client.head_bucket(Bucket=results_bucket)
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    def test_data_file_uploaded(self, deployed_env, aws_clients: AWSClients):
        """Test that the CSV data file was uploaded."""
        bucket_name = deployed_env.get("BUCKET_NAME")

        response = aws_clients.s3_client.get_object(
            Bucket=bucket_name,
            Key="data.csv",
        )
        content = response["Body"].read().decode("utf-8")
        assert "Item" in content  # Header row
        assert "Deadpool DVD" in content  # Data row

    def test_vault_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the Glacier vault was created."""
        vault_name = deployed_env.get("VAULT_NAME")
        assert vault_name, "VAULT_NAME should be set"

        response = aws_clients.glacier_client.describe_vault(
            accountId="-",
            vaultName=vault_name,
        )
        assert response["VaultName"] == vault_name

    def test_archive_uploaded(self, deployed_env, aws_clients: AWSClients):
        """Test that an archive was uploaded to the vault."""
        archive_id = deployed_env.get("ARCHIVE_ID")
        assert archive_id, "ARCHIVE_ID should be set"
        assert len(archive_id) > 0

    def test_s3_select_query(self, deployed_env, aws_clients: AWSClients):
        """Test S3 Select query on CSV data."""
        bucket_name = deployed_env.get("BUCKET_NAME")

        # Run S3 Select query to count rows and sum Cost column
        response = aws_clients.s3_client.select_object_content(
            Bucket=bucket_name,
            Key="data.csv",
            ExpressionType="SQL",
            Expression="SELECT COUNT(*), SUM(CAST(Cost AS FLOAT)) FROM s3object",
            InputSerialization={
                "CSV": {
                    "FileHeaderInfo": "USE",
                }
            },
            OutputSerialization={
                "CSV": {}
            },
        )

        # Process the streaming response
        result = ""
        for event in response["Payload"]:
            if "Records" in event:
                result += event["Records"]["Payload"].decode("utf-8")

        # Should have 10 rows and sum approximately 68.44
        assert "10" in result

    def test_s3_select_filter_query(self, deployed_env, aws_clients: AWSClients):
        """Test S3 Select with WHERE clause."""
        bucket_name = deployed_env.get("BUCKET_NAME")

        # Query for items with Cost > 10
        response = aws_clients.s3_client.select_object_content(
            Bucket=bucket_name,
            Key="data.csv",
            ExpressionType="SQL",
            Expression="SELECT Item FROM s3object WHERE CAST(Cost AS FLOAT) > 10",
            InputSerialization={
                "CSV": {
                    "FileHeaderInfo": "USE",
                }
            },
            OutputSerialization={
                "CSV": {}
            },
        )

        # Process the streaming response
        result = ""
        for event in response["Payload"]:
            if "Records" in event:
                result += event["Records"]["Payload"].decode("utf-8")

        # Deadpool DVD costs 14.96
        assert "Deadpool" in result
