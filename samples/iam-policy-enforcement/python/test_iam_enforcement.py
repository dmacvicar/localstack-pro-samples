"""
Tests for IAM Policy Enforcement sample.

IMPORTANT: This sample requires LocalStack to be started with ENFORCE_IAM=1.
Tests will be skipped if IAM enforcement is not enabled.

Run all IaC methods:
    uv run pytest samples/iam-policy-enforcement/python/ -v

Run specific IaC method:
    uv run pytest samples/iam-policy-enforcement/python/ -v -k scripts
"""

import sys
from pathlib import Path

import boto3
import pytest
from botocore.exceptions import ClientError

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

SAMPLE_NAME = "iam-policy-enforcement"
LANGUAGE = "python"

# IaC methods to test
IAC_METHODS = ["scripts"]


def iam_client(access_key: str = None, secret_key: str = None):
    """Create IAM client with optional custom credentials."""
    return boto3.client(
        "iam",
        endpoint_url=LOCALSTACK_ENDPOINT,
        region_name="us-east-1",
        aws_access_key_id=access_key or AWS_ACCESS_KEY_ID,
        aws_secret_access_key=secret_key or AWS_SECRET_ACCESS_KEY,
    )


def kinesis_client(access_key: str = None, secret_key: str = None):
    """Create Kinesis client with optional custom credentials."""
    return boto3.client(
        "kinesis",
        endpoint_url=LOCALSTACK_ENDPOINT,
        region_name="us-east-1",
        aws_access_key_id=access_key or AWS_ACCESS_KEY_ID,
        aws_secret_access_key=secret_key or AWS_SECRET_ACCESS_KEY,
    )


def s3_client(access_key: str = None, secret_key: str = None):
    """Create S3 client with optional custom credentials."""
    return boto3.client(
        "s3",
        endpoint_url=LOCALSTACK_ENDPOINT,
        region_name="us-east-1",
        aws_access_key_id=access_key or AWS_ACCESS_KEY_ID,
        aws_secret_access_key=secret_key or AWS_SECRET_ACCESS_KEY,
    )


@pytest.fixture(scope="module", params=IAC_METHODS)
def deployed_env(request, aws_clients: AWSClients, wait_for: WaitFor):
    """Deploy the sample and return environment variables."""
    iac_method = request.param

    sample_dir = get_sample_dir(SAMPLE_NAME, LANGUAGE)
    deploy_path = sample_dir / iac_method / "deploy.sh"

    if not deploy_path.exists():
        pytest.skip(f"Deploy script not found: {deploy_path}")

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method, timeout=60)
    env["_IAC_METHOD"] = iac_method

    return env


@pytest.fixture
def require_iam_enforcement(deployed_env):
    """Skip test if IAM enforcement is not enabled."""
    if deployed_env.get("IAM_ENFORCED") != "true":
        pytest.skip("IAM enforcement not enabled (start LocalStack with ENFORCE_IAM=1)")
    return deployed_env


class TestIamEnforcement:
    """Test IAM policy enforcement functionality."""

    def test_user_exists(self, deployed_env):
        """Test that the IAM user was created."""
        user_name = deployed_env.get("USER_NAME")
        assert user_name, "USER_NAME should be set"

        client = iam_client()
        response = client.get_user(UserName=user_name)
        assert response["User"]["UserName"] == user_name

    def test_policy_exists(self, deployed_env):
        """Test that the IAM policy was created."""
        policy_arn = deployed_env.get("POLICY_ARN")
        assert policy_arn, "POLICY_ARN should be set"

        client = iam_client()
        response = client.get_policy(PolicyArn=policy_arn)
        assert response["Policy"]["Arn"] == policy_arn

    def test_policy_attached_to_user(self, deployed_env):
        """Test that the policy is attached to the user."""
        user_name = deployed_env.get("USER_NAME")
        policy_arn = deployed_env.get("POLICY_ARN")

        client = iam_client()
        response = client.list_attached_user_policies(UserName=user_name)
        policy_arns = [p["PolicyArn"] for p in response["AttachedPolicies"]]
        assert policy_arn in policy_arns

    def test_access_key_created(self, deployed_env):
        """Test that access key was created for the user."""
        access_key_id = deployed_env.get("IAM_ACCESS_KEY_ID")
        assert access_key_id, "IAM_ACCESS_KEY_ID should be set"
        assert len(access_key_id) > 0

    def test_default_credentials_denied_kinesis(self, require_iam_enforcement):
        """Test that default credentials are denied for Kinesis."""
        env = require_iam_enforcement
        client = kinesis_client()

        with pytest.raises(ClientError) as exc_info:
            client.create_stream(StreamName="test-denied-stream", ShardCount=1)

        assert exc_info.value.response["Error"]["Code"] == "AccessDeniedException"

    def test_default_credentials_denied_s3(self, require_iam_enforcement):
        """Test that default credentials are denied for S3."""
        env = require_iam_enforcement
        client = s3_client()

        with pytest.raises(ClientError) as exc_info:
            client.create_bucket(Bucket="test-denied-bucket")

        assert exc_info.value.response["Error"]["Code"] == "AccessDeniedException"

    def test_iam_user_allowed_kinesis(self, require_iam_enforcement):
        """Test that IAM user credentials are allowed for Kinesis."""
        env = require_iam_enforcement
        access_key = env.get("IAM_ACCESS_KEY_ID")
        secret_key = env.get("IAM_SECRET_ACCESS_KEY")

        client = kinesis_client(access_key, secret_key)

        # Should succeed with IAM user credentials
        client.create_stream(StreamName="iam-test-stream", ShardCount=1)

        # Verify stream exists
        response = client.describe_stream(StreamName="iam-test-stream")
        assert response["StreamDescription"]["StreamName"] == "iam-test-stream"

        # Clean up
        client.delete_stream(StreamName="iam-test-stream")

    def test_iam_user_allowed_s3(self, require_iam_enforcement):
        """Test that IAM user credentials are allowed for S3."""
        env = require_iam_enforcement
        access_key = env.get("IAM_ACCESS_KEY_ID")
        secret_key = env.get("IAM_SECRET_ACCESS_KEY")

        client = s3_client(access_key, secret_key)

        # Should succeed with IAM user credentials
        client.create_bucket(Bucket="iam-test-bucket")

        # Verify bucket exists
        response = client.list_buckets()
        bucket_names = [b["Name"] for b in response["Buckets"]]
        assert "iam-test-bucket" in bucket_names

        # Clean up
        client.delete_bucket(Bucket="iam-test-bucket")
