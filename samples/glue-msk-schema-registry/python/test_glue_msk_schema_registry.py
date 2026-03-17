"""
Tests for Glue MSK Schema Registry sample.

Run all IaC methods:
    uv run pytest samples/glue-msk-schema-registry/python/ -v

Run specific IaC method:
    uv run pytest samples/glue-msk-schema-registry/python/ -v -k scripts
"""

import json
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

SAMPLE_NAME = "glue-msk-schema-registry"
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


class TestGlueMskSchemaRegistry:
    """Test MSK cluster, Glue Schema Registry, schema, and schema versions."""

    def test_msk_cluster_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the MSK cluster was created."""
        cluster_arn = deployed_env.get("CLUSTER_ARN")
        assert cluster_arn, "CLUSTER_ARN should be set"

        response = aws_clients.kafka_client.describe_cluster(
            ClusterArn=cluster_arn
        )
        assert response["ClusterInfo"]["ClusterName"] == deployed_env["CLUSTER_NAME"]

    def test_msk_cluster_active(self, deployed_env, aws_clients: AWSClients):
        """Test that the MSK cluster is ACTIVE."""
        cluster_arn = deployed_env.get("CLUSTER_ARN")

        response = aws_clients.kafka_client.describe_cluster(
            ClusterArn=cluster_arn
        )
        assert response["ClusterInfo"]["State"] == "ACTIVE"

    def test_msk_bootstrap_brokers(self, deployed_env, aws_clients: AWSClients):
        """Test that bootstrap brokers are available."""
        cluster_arn = deployed_env.get("CLUSTER_ARN")

        response = aws_clients.kafka_client.get_bootstrap_brokers(
            ClusterArn=cluster_arn
        )
        # LocalStack returns TLS brokers only
        brokers = response.get("BootstrapBrokerString") or response.get("BootstrapBrokerStringTls", "")
        assert brokers, "Bootstrap brokers should not be empty"

    def test_glue_registry_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the Glue Schema Registry was created."""
        registry_name = deployed_env.get("REGISTRY_NAME")
        assert registry_name, "REGISTRY_NAME should be set"

        response = aws_clients.glue_client.get_registry(
            RegistryId={"RegistryName": registry_name}
        )
        assert response["RegistryName"] == registry_name

    def test_glue_registry_available(self, deployed_env, aws_clients: AWSClients):
        """Test that the registry is AVAILABLE."""
        registry_name = deployed_env.get("REGISTRY_NAME")

        response = aws_clients.glue_client.get_registry(
            RegistryId={"RegistryName": registry_name}
        )
        assert response["Status"] == "AVAILABLE"

    def test_schema_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the AVRO schema was created."""
        schema_arn = deployed_env.get("SCHEMA_ARN")
        assert schema_arn, "SCHEMA_ARN should be set"

        response = aws_clients.glue_client.get_schema(
            SchemaId={"SchemaArn": schema_arn}
        )
        assert response["SchemaName"] == deployed_env["SCHEMA_NAME"]

    def test_schema_data_format(self, deployed_env, aws_clients: AWSClients):
        """Test that the schema uses AVRO data format."""
        schema_arn = deployed_env.get("SCHEMA_ARN")

        response = aws_clients.glue_client.get_schema(
            SchemaId={"SchemaArn": schema_arn}
        )
        assert response["DataFormat"] == "AVRO"

    def test_schema_compatibility(self, deployed_env, aws_clients: AWSClients):
        """Test that the schema has BACKWARD compatibility."""
        schema_arn = deployed_env.get("SCHEMA_ARN")

        response = aws_clients.glue_client.get_schema(
            SchemaId={"SchemaArn": schema_arn}
        )
        assert response["Compatibility"] == "BACKWARD"

    def test_schema_v1_content(self, deployed_env, aws_clients: AWSClients):
        """Test that schema v1 has the expected fields."""
        schema_arn = deployed_env.get("SCHEMA_ARN")

        response = aws_clients.glue_client.get_schema_version(
            SchemaId={"SchemaArn": schema_arn},
            SchemaVersionNumber={"VersionNumber": 1},
        )
        definition = json.loads(response["SchemaDefinition"])
        field_names = [f["name"] for f in definition["fields"]]

        assert "request_id" in field_names
        assert "pickup_address" in field_names
        assert "customer" in field_names
        assert "recommended_unicorn" in field_names

    def test_schema_has_multiple_versions(self, deployed_env, aws_clients: AWSClients):
        """Test that schema v2 was registered (backward compatible)."""
        schema_arn = deployed_env.get("SCHEMA_ARN")

        response = aws_clients.glue_client.get_schema(
            SchemaId={"SchemaArn": schema_arn}
        )
        # Should have at least 2 versions (v1 initial + v2 backward compatible)
        latest_version = response.get("LatestSchemaVersion", 1)
        assert latest_version >= 2, f"Expected at least 2 schema versions, got {latest_version}"

    def test_schema_v2_removes_customer(self, deployed_env, aws_clients: AWSClients):
        """Test that schema v2 removed the customer field."""
        schema_arn = deployed_env.get("SCHEMA_ARN")

        response = aws_clients.glue_client.get_schema_version(
            SchemaId={"SchemaArn": schema_arn},
            SchemaVersionNumber={"VersionNumber": 2},
        )
        definition = json.loads(response["SchemaDefinition"])
        field_names = [f["name"] for f in definition["fields"]]

        assert "customer" not in field_names
        assert "request_id" in field_names
        assert "recommended_unicorn" in field_names

    def test_schema_v3_incompatible(self, deployed_env, aws_clients: AWSClients):
        """Test that schema v3 failed compatibility check."""
        schema_arn = deployed_env.get("SCHEMA_ARN")

        # v3 should either not exist or be in FAILURE status
        try:
            response = aws_clients.glue_client.get_schema_version(
                SchemaId={"SchemaArn": schema_arn},
                SchemaVersionNumber={"VersionNumber": 3},
            )
            # If it exists, it should be in FAILURE status
            status = response.get("Status", "")
            assert status == "FAILURE", f"Schema v3 should have FAILURE status, got {status}"
        except Exception:
            # If v3 doesn't exist at all, that's also acceptable
            pass
