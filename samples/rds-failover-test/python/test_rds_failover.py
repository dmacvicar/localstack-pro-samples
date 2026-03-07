"""
Tests for RDS Global Cluster Failover sample.

Run all IaC methods:
    uv run pytest samples/rds-failover-test/python/ -v

Run specific IaC method:
    uv run pytest samples/rds-failover-test/python/ -v -k scripts
"""

import sys
import time
from pathlib import Path

import boto3
import pytest

# Add samples directory to path for conftest imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from conftest import (
    AWSClients,
    WaitFor,
    run_deploy,
    get_sample_dir,
    LOCALSTACK_ENDPOINT,
    AWS_ACCESS_KEY_ID,
    AWS_SECRET_ACCESS_KEY,
)

SAMPLE_NAME = "rds-failover-test"
LANGUAGE = "python"

# IaC methods to test
IAC_METHODS = ["scripts", "terraform", "cloudformation", "cdk"]


def rds_client(region: str = "us-east-1"):
    """Create RDS client for specific region."""
    return boto3.client(
        "rds",
        endpoint_url=LOCALSTACK_ENDPOINT,
        region_name=region,
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
    )


@pytest.fixture(scope="module", params=IAC_METHODS)
def deployed_env(request, aws_clients: AWSClients, wait_for: WaitFor):
    """Deploy the sample and return environment variables."""
    iac_method = request.param

    sample_dir = get_sample_dir(SAMPLE_NAME, LANGUAGE)
    deploy_path = sample_dir / iac_method / "deploy.sh"

    if not deploy_path.exists():
        pytest.skip(f"Deploy script not found: {deploy_path}")

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method, timeout=180)
    env["_IAC_METHOD"] = iac_method

    return env


class TestRdsFailover:
    """Test RDS global cluster failover functionality."""

    def test_global_cluster_exists(self, deployed_env):
        """Test that the global cluster was created."""
        global_cluster_id = deployed_env.get("GLOBAL_CLUSTER_ID")
        assert global_cluster_id, "GLOBAL_CLUSTER_ID should be set"

        client = rds_client()
        response = client.describe_global_clusters(
            GlobalClusterIdentifier=global_cluster_id
        )
        assert len(response["GlobalClusters"]) == 1
        assert response["GlobalClusters"][0]["GlobalClusterIdentifier"] == global_cluster_id

    def test_primary_cluster_exists(self, deployed_env):
        """Test that the primary cluster was created."""
        primary_cluster_id = deployed_env.get("PRIMARY_CLUSTER_ID")

        client = rds_client("us-east-1")
        response = client.describe_db_clusters(
            DBClusterIdentifier=primary_cluster_id
        )
        assert len(response["DBClusters"]) == 1
        assert response["DBClusters"][0]["Engine"] == "aurora-postgresql"

    def test_secondary_cluster_exists(self, deployed_env):
        """Test that the secondary cluster was created."""
        secondary_cluster_id = deployed_env.get("SECONDARY_CLUSTER_ID")

        client = rds_client("us-west-1")
        response = client.describe_db_clusters(
            DBClusterIdentifier=secondary_cluster_id
        )
        assert len(response["DBClusters"]) == 1

    def test_global_cluster_has_members(self, deployed_env):
        """Test that the global cluster has both primary and secondary members."""
        global_cluster_id = deployed_env.get("GLOBAL_CLUSTER_ID")

        client = rds_client()
        response = client.describe_global_clusters(
            GlobalClusterIdentifier=global_cluster_id
        )
        members = response["GlobalClusters"][0]["GlobalClusterMembers"]
        assert len(members) >= 2

    def test_primary_is_writer(self, deployed_env):
        """Test that the primary cluster is marked as writer."""
        global_cluster_id = deployed_env.get("GLOBAL_CLUSTER_ID")
        primary_arn = deployed_env.get("PRIMARY_ARN")

        client = rds_client()
        response = client.describe_global_clusters(
            GlobalClusterIdentifier=global_cluster_id
        )
        members = response["GlobalClusters"][0]["GlobalClusterMembers"]
        members_map = {m["DBClusterArn"]: m for m in members}

        assert primary_arn in members_map
        assert members_map[primary_arn]["IsWriter"] is True

    def test_secondary_is_not_writer(self, deployed_env):
        """Test that the secondary cluster is not marked as writer."""
        global_cluster_id = deployed_env.get("GLOBAL_CLUSTER_ID")
        secondary_arn = deployed_env.get("SECONDARY_ARN")

        client = rds_client()
        response = client.describe_global_clusters(
            GlobalClusterIdentifier=global_cluster_id
        )
        members = response["GlobalClusters"][0]["GlobalClusterMembers"]
        members_map = {m["DBClusterArn"]: m for m in members}

        assert secondary_arn in members_map
        assert members_map[secondary_arn]["IsWriter"] is False

    def test_failover(self, deployed_env):
        """Test global cluster failover from primary to secondary."""
        global_cluster_id = deployed_env.get("GLOBAL_CLUSTER_ID")
        secondary_arn = deployed_env.get("SECONDARY_ARN")

        client = rds_client()

        # Initiate failover
        client.failover_global_cluster(
            GlobalClusterIdentifier=global_cluster_id,
            TargetDbClusterIdentifier=secondary_arn,
        )

        # Wait for failover to complete
        for _ in range(40):
            response = client.describe_global_clusters(
                GlobalClusterIdentifier=global_cluster_id
            )
            failover_state = response["GlobalClusters"][0].get("FailoverState")
            if not failover_state:
                break
            time.sleep(1)

        # Verify secondary is now the writer
        response = client.describe_global_clusters(
            GlobalClusterIdentifier=global_cluster_id
        )
        members = response["GlobalClusters"][0]["GlobalClusterMembers"]
        members_map = {m["DBClusterArn"]: m for m in members}

        assert members_map[secondary_arn]["IsWriter"] is True
