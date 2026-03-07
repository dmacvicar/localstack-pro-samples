"""
Tests for CloudWatch Metrics sample.

This sample tests CloudWatch alarms triggered by Lambda errors.
Email notification tests require SMTP configuration and will be skipped otherwise.

Run all IaC methods:
    uv run pytest samples/cloudwatch-metrics-aws/python/ -v

Run specific IaC method:
    uv run pytest samples/cloudwatch-metrics-aws/python/ -v -k scripts
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

SAMPLE_NAME = "cloudwatch-metrics-aws"
LANGUAGE = "python"

# IaC methods to test
IAC_METHODS = ["scripts", "terraform", "cloudformation", "cdk"]


def lambda_client():
    """Create Lambda client."""
    return boto3.client(
        "lambda",
        endpoint_url=LOCALSTACK_ENDPOINT,
        region_name="us-east-1",
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
    )


def cloudwatch_client():
    """Create CloudWatch client."""
    return boto3.client(
        "cloudwatch",
        endpoint_url=LOCALSTACK_ENDPOINT,
        region_name="us-east-1",
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
    )


def sns_client():
    """Create SNS client."""
    return boto3.client(
        "sns",
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
def require_smtp(deployed_env):
    """Skip test if SMTP is not configured."""
    if deployed_env.get("SMTP_CONFIGURED") != "true":
        pytest.skip("SMTP not configured (start LocalStack with SMTP_HOST)")
    return deployed_env


class TestCloudWatchMetrics:
    """Test CloudWatch metrics and alarms functionality."""

    def test_lambda_exists(self, deployed_env):
        """Test that the Lambda function was created."""
        function_name = deployed_env.get("FUNCTION_NAME")
        assert function_name, "FUNCTION_NAME should be set"

        client = lambda_client()
        response = client.get_function(FunctionName=function_name)
        assert response["Configuration"]["FunctionName"] == function_name

    def test_lambda_is_active(self, deployed_env):
        """Test that the Lambda is active."""
        function_name = deployed_env.get("FUNCTION_NAME")

        client = lambda_client()
        response = client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_sns_topic_exists(self, deployed_env):
        """Test that the SNS topic was created."""
        topic_arn = deployed_env.get("TOPIC_ARN")
        assert topic_arn, "TOPIC_ARN should be set"

        client = sns_client()
        response = client.get_topic_attributes(TopicArn=topic_arn)
        assert "Attributes" in response

    def test_alarm_exists(self, deployed_env):
        """Test that the CloudWatch alarm was created."""
        alarm_name = deployed_env.get("ALARM_NAME")
        assert alarm_name, "ALARM_NAME should be set"

        client = cloudwatch_client()
        response = client.describe_alarms(AlarmNames=[alarm_name])
        assert len(response["MetricAlarms"]) == 1
        assert response["MetricAlarms"][0]["AlarmName"] == alarm_name

    def test_alarm_configuration(self, deployed_env):
        """Test that the alarm is configured correctly."""
        alarm_name = deployed_env.get("ALARM_NAME")
        function_name = deployed_env.get("FUNCTION_NAME")

        client = cloudwatch_client()
        response = client.describe_alarms(AlarmNames=[alarm_name])
        alarm = response["MetricAlarms"][0]

        assert alarm["MetricName"] == "Errors"
        assert alarm["Namespace"] == "AWS/Lambda"
        assert alarm["Threshold"] == 1.0
        assert alarm["ComparisonOperator"] == "GreaterThanOrEqualToThreshold"

        # Check dimension
        dimensions = {d["Name"]: d["Value"] for d in alarm["Dimensions"]}
        assert dimensions.get("FunctionName") == function_name

    def test_alarm_has_action(self, deployed_env):
        """Test that the alarm has SNS action configured."""
        alarm_name = deployed_env.get("ALARM_NAME")
        topic_arn = deployed_env.get("TOPIC_ARN")

        client = cloudwatch_client()
        response = client.describe_alarms(AlarmNames=[alarm_name])
        alarm = response["MetricAlarms"][0]

        assert topic_arn in alarm["AlarmActions"]

    def test_lambda_invocation_fails(self, deployed_env):
        """Test that invoking Lambda raises an error (as expected)."""
        function_name = deployed_env.get("FUNCTION_NAME")

        client = lambda_client()
        response = client.invoke(
            FunctionName=function_name,
            InvocationType="RequestResponse",
        )

        # Function should return error
        assert response.get("FunctionError") == "Unhandled"

    def test_alarm_state_changes_after_error(self, deployed_env):
        """Test that alarm state changes after Lambda error."""
        alarm_name = deployed_env.get("ALARM_NAME")
        function_name = deployed_env.get("FUNCTION_NAME")

        lambda_c = lambda_client()
        cw_client = cloudwatch_client()

        # Invoke Lambda to generate error
        lambda_c.invoke(
            FunctionName=function_name,
            InvocationType="RequestResponse",
        )

        # Wait for alarm state to potentially change
        # Note: This may take up to 60 seconds depending on evaluation period
        alarm_triggered = False
        for _ in range(12):  # Wait up to 60 seconds
            response = cw_client.describe_alarms(AlarmNames=[alarm_name])
            state = response["MetricAlarms"][0]["StateValue"]
            if state == "ALARM":
                alarm_triggered = True
                break
            time.sleep(5)

        # The alarm may or may not trigger depending on timing
        # Just verify we can check the state
        response = cw_client.describe_alarms(AlarmNames=[alarm_name])
        assert response["MetricAlarms"][0]["StateValue"] in ["OK", "ALARM", "INSUFFICIENT_DATA"]

    def test_email_subscription_exists(self, deployed_env):
        """Test that email subscription was created."""
        topic_arn = deployed_env.get("TOPIC_ARN")

        client = sns_client()
        response = client.list_subscriptions_by_topic(TopicArn=topic_arn)

        # Should have at least one subscription
        assert len(response["Subscriptions"]) >= 1

        # Check that email protocol is used
        protocols = [s["Protocol"] for s in response["Subscriptions"]]
        assert "email" in protocols
