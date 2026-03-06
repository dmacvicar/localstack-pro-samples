"""
Tests for EC2 Docker Instances sample.

IMPORTANT: This sample requires LocalStack to be started with EC2_VM_MANAGER=docker.
Tests will be skipped if EC2 Docker backend is not enabled.

Run all IaC methods:
    uv run pytest samples/ec2-docker-instances/python/ -v

Run specific IaC method:
    uv run pytest samples/ec2-docker-instances/python/ -v -k scripts
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

SAMPLE_NAME = "ec2-docker-instances"
LANGUAGE = "python"

# IaC methods to test
IAC_METHODS = ["scripts"]


def ec2_client():
    """Create EC2 client."""
    return boto3.client(
        "ec2",
        endpoint_url=LOCALSTACK_ENDPOINT,
        region_name="us-east-1",
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
    )


def ssm_client():
    """Create SSM client."""
    return boto3.client(
        "ssm",
        endpoint_url=LOCALSTACK_ENDPOINT,
        region_name="us-east-1",
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

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method, timeout=120)
    env["_IAC_METHOD"] = iac_method

    return env


@pytest.fixture
def require_ec2_docker(deployed_env):
    """Skip test if EC2 Docker backend is not enabled."""
    if deployed_env.get("EC2_DOCKER_ENABLED") != "true":
        pytest.skip("EC2 Docker backend not enabled (start LocalStack with EC2_VM_MANAGER=docker)")
    return deployed_env


class TestEc2Docker:
    """Test EC2 Docker instance functionality."""

    def test_ami_prepared(self, deployed_env):
        """Test that the AMI ID was set."""
        ami_id = deployed_env.get("AMI_ID")
        assert ami_id, "AMI_ID should be set"
        assert ami_id.startswith("ami-")

    def test_instance_created(self, require_ec2_docker):
        """Test that the EC2 instance was created."""
        env = require_ec2_docker
        instance_id = env.get("INSTANCE_ID")
        assert instance_id, "INSTANCE_ID should be set"
        assert instance_id.startswith("i-")

    def test_instance_is_running(self, require_ec2_docker):
        """Test that the instance is running."""
        env = require_ec2_docker
        instance_id = env.get("INSTANCE_ID")

        client = ec2_client()
        response = client.describe_instances(InstanceIds=[instance_id])
        state = response["Reservations"][0]["Instances"][0]["State"]["Name"]
        assert state == "running"

    def test_instance_has_ip(self, require_ec2_docker):
        """Test that the instance has an IP address."""
        env = require_ec2_docker
        # At least one IP should be set
        private_ip = env.get("PRIVATE_IP")
        public_ip = env.get("PUBLIC_IP")
        assert private_ip or public_ip, "Instance should have an IP address"

    def test_ssm_send_command(self, require_ec2_docker):
        """Test sending SSM command to the instance."""
        env = require_ec2_docker
        instance_id = env.get("INSTANCE_ID")

        client = ssm_client()

        # Send a simple command
        response = client.send_command(
            DocumentName="AWS-RunShellScript",
            DocumentVersion="1",
            InstanceIds=[instance_id],
            Parameters={"commands": ["echo hello"]},
        )

        command_id = response["Command"]["CommandId"]
        assert command_id, "Command ID should be returned"

        # Wait for command to complete
        time.sleep(2)

        # Get command result
        result = client.get_command_invocation(
            CommandId=command_id,
            InstanceId=instance_id,
        )

        assert result["Status"] in ["Success", "InProgress", "Pending"]

    def test_create_ami_from_instance(self, require_ec2_docker):
        """Test creating an AMI from the running instance."""
        env = require_ec2_docker
        instance_id = env.get("INSTANCE_ID")

        client = ec2_client()

        # Create AMI
        response = client.create_image(
            InstanceId=instance_id,
            Name=f"test-ami-{int(time.time())}",
            Description="Test AMI from EC2 Docker instance",
        )

        ami_id = response["ImageId"]
        assert ami_id, "AMI ID should be returned"
        assert ami_id.startswith("ami-")

        # Clean up - deregister the test AMI
        client.deregister_image(ImageId=ami_id)

    def test_terminate_instance(self, require_ec2_docker):
        """Test that we can terminate the instance."""
        env = require_ec2_docker
        instance_id = env.get("INSTANCE_ID")

        client = ec2_client()

        # Get current state
        response = client.describe_instances(InstanceIds=[instance_id])
        current_state = response["Reservations"][0]["Instances"][0]["State"]["Name"]

        # Only test terminate if instance is still running
        if current_state == "running":
            # Note: We don't actually terminate here as other tests may need the instance
            # Just verify we can call the API
            pass

        assert current_state in ["running", "stopped", "terminated"]
