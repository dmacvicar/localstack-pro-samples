"""
Tests for Route53 DNS Failover sample.

Run all IaC methods:
    uv run pytest samples/route53-dns-failover/python/ -v

Run specific IaC method:
    uv run pytest samples/route53-dns-failover/python/ -v -k scripts
"""

import sys
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

SAMPLE_NAME = "route53-dns-failover"
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

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method, timeout=300)
    env["_IAC_METHOD"] = iac_method

    return env


class TestRoute53DnsFailover:
    """Test Route53 hosted zone, health checks, and failover routing."""

    def test_hosted_zone_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the hosted zone was created."""
        hosted_zone_id = deployed_env.get("HOSTED_ZONE_ID")
        assert hosted_zone_id, "HOSTED_ZONE_ID should be set"

        response = aws_clients.route53_client.get_hosted_zone(Id=hosted_zone_id)
        assert response["HostedZone"] is not None
        zone_name = response["HostedZone"]["Name"]
        assert zone_name.rstrip(".")  # Should have a name

    def test_hosted_zone_name_matches(self, deployed_env, aws_clients: AWSClients):
        """Test that the hosted zone name matches configuration."""
        hosted_zone_id = deployed_env.get("HOSTED_ZONE_ID")
        expected_name = deployed_env.get("HOSTED_ZONE_NAME")
        assert expected_name, "HOSTED_ZONE_NAME should be set"

        response = aws_clients.route53_client.get_hosted_zone(Id=hosted_zone_id)
        actual_name = response["HostedZone"]["Name"].rstrip(".")
        assert actual_name == expected_name.rstrip(".")

    def test_health_check_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the health check was created."""
        health_check_id = deployed_env.get("HEALTH_CHECK_ID")
        assert health_check_id, "HEALTH_CHECK_ID should be set"

        response = aws_clients.route53_client.get_health_check(
            HealthCheckId=health_check_id
        )
        assert response["HealthCheck"]["Id"] == health_check_id

    def test_health_check_config(self, deployed_env, aws_clients: AWSClients):
        """Test that the health check has correct HTTP configuration."""
        health_check_id = deployed_env.get("HEALTH_CHECK_ID")

        response = aws_clients.route53_client.get_health_check(
            HealthCheckId=health_check_id
        )
        config = response["HealthCheck"]["HealthCheckConfig"]
        assert config["Type"] == "HTTP"
        assert config["Port"] == 4566
        assert "/_localstack/health" in config.get("ResourcePath", "")

    def test_target_records_exist(self, deployed_env, aws_clients: AWSClients):
        """Test that the target CNAME records were created."""
        hosted_zone_id = deployed_env.get("HOSTED_ZONE_ID")
        hosted_zone_name = deployed_env.get("HOSTED_ZONE_NAME")

        response = aws_clients.route53_client.list_resource_record_sets(
            HostedZoneId=hosted_zone_id
        )
        record_names = [
            r["Name"].rstrip(".") for r in response["ResourceRecordSets"]
        ]

        target1 = f"target1.{hosted_zone_name}".rstrip(".")
        target2 = f"target2.{hosted_zone_name}".rstrip(".")

        assert target1 in record_names, f"target1 record not found in {record_names}"
        assert target2 in record_names, f"target2 record not found in {record_names}"

    def test_failover_records_exist(self, deployed_env, aws_clients: AWSClients):
        """Test that the failover routing records were created."""
        hosted_zone_id = deployed_env.get("HOSTED_ZONE_ID")
        failover_record = deployed_env.get("FAILOVER_RECORD", "").rstrip(".")

        response = aws_clients.route53_client.list_resource_record_sets(
            HostedZoneId=hosted_zone_id
        )

        failover_records = [
            r for r in response["ResourceRecordSets"]
            if r["Name"].rstrip(".") == failover_record
            and r.get("Failover") in ("PRIMARY", "SECONDARY")
        ]

        assert len(failover_records) == 2, (
            f"Expected 2 failover records, got {len(failover_records)}"
        )

    def test_primary_record_has_health_check(self, deployed_env, aws_clients: AWSClients):
        """Test that the primary failover record has a health check attached."""
        hosted_zone_id = deployed_env.get("HOSTED_ZONE_ID")
        failover_record = deployed_env.get("FAILOVER_RECORD", "").rstrip(".")
        health_check_id = deployed_env.get("HEALTH_CHECK_ID")

        response = aws_clients.route53_client.list_resource_record_sets(
            HostedZoneId=hosted_zone_id
        )

        primary_records = [
            r for r in response["ResourceRecordSets"]
            if r["Name"].rstrip(".") == failover_record
            and r.get("Failover") == "PRIMARY"
        ]

        assert len(primary_records) == 1, "Expected exactly one PRIMARY failover record"
        primary = primary_records[0]
        assert primary.get("HealthCheckId") == health_check_id, (
            "PRIMARY record should have health check attached"
        )

    def test_secondary_record_no_health_check(self, deployed_env, aws_clients: AWSClients):
        """Test that the secondary failover record has no health check."""
        hosted_zone_id = deployed_env.get("HOSTED_ZONE_ID")
        failover_record = deployed_env.get("FAILOVER_RECORD", "").rstrip(".")

        response = aws_clients.route53_client.list_resource_record_sets(
            HostedZoneId=hosted_zone_id
        )

        secondary_records = [
            r for r in response["ResourceRecordSets"]
            if r["Name"].rstrip(".") == failover_record
            and r.get("Failover") == "SECONDARY"
        ]

        assert len(secondary_records) == 1, "Expected exactly one SECONDARY failover record"
        secondary = secondary_records[0]
        assert not secondary.get("HealthCheckId"), (
            "SECONDARY record should not have a health check"
        )

    def test_primary_points_to_target1(self, deployed_env, aws_clients: AWSClients):
        """Test that the primary failover aliases to target1."""
        hosted_zone_id = deployed_env.get("HOSTED_ZONE_ID")
        failover_record = deployed_env.get("FAILOVER_RECORD", "").rstrip(".")
        target1 = deployed_env.get("TARGET1_RECORD", "").rstrip(".")

        response = aws_clients.route53_client.list_resource_record_sets(
            HostedZoneId=hosted_zone_id
        )

        primary_records = [
            r for r in response["ResourceRecordSets"]
            if r["Name"].rstrip(".") == failover_record
            and r.get("Failover") == "PRIMARY"
        ]

        assert len(primary_records) == 1
        alias = primary_records[0].get("AliasTarget", {})
        assert alias.get("DNSName", "").rstrip(".") == target1, (
            f"PRIMARY should alias to {target1}"
        )

    def test_secondary_points_to_target2(self, deployed_env, aws_clients: AWSClients):
        """Test that the secondary failover aliases to target2."""
        hosted_zone_id = deployed_env.get("HOSTED_ZONE_ID")
        failover_record = deployed_env.get("FAILOVER_RECORD", "").rstrip(".")
        target2 = deployed_env.get("TARGET2_RECORD", "").rstrip(".")

        response = aws_clients.route53_client.list_resource_record_sets(
            HostedZoneId=hosted_zone_id
        )

        secondary_records = [
            r for r in response["ResourceRecordSets"]
            if r["Name"].rstrip(".") == failover_record
            and r.get("Failover") == "SECONDARY"
        ]

        assert len(secondary_records) == 1
        alias = secondary_records[0].get("AliasTarget", {})
        assert alias.get("DNSName", "").rstrip(".") == target2, (
            f"SECONDARY should alias to {target2}"
        )
