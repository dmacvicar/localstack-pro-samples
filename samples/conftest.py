"""
Shared pytest fixtures for LocalStack Pro Samples.

Run from project root:
    uv run pytest samples/

Run a specific sample:
    uv run pytest samples/lambda-function-urls/python/ -v

Tests are parameterized by sample and IaC method (scripts, terraform, cloudformation, cdk).
"""

import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path

import boto3
import pytest
import requests
from tenacity import (
    retry,
    stop_after_delay,
    wait_fixed,
)


# =============================================================================
# Configuration
# =============================================================================

LOCALSTACK_ENDPOINT = os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566")
AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID", "test")
AWS_SECRET_ACCESS_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY", "test")

SAMPLES_DIR = Path(__file__).parent


# =============================================================================
# AWS Clients
# =============================================================================

@dataclass
class AWSClients:
    """Container for AWS service clients configured for LocalStack."""

    endpoint_url: str
    region: str

    def _client(self, service: str):
        return boto3.client(
            service,
            endpoint_url=self.endpoint_url,
            region_name=self.region,
            aws_access_key_id=AWS_ACCESS_KEY_ID,
            aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
        )

    def _resource(self, service: str):
        return boto3.resource(
            service,
            endpoint_url=self.endpoint_url,
            region_name=self.region,
            aws_access_key_id=AWS_ACCESS_KEY_ID,
            aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
        )

    @property
    def lambda_client(self):
        return self._client("lambda")

    @property
    def dynamodb_client(self):
        return self._client("dynamodb")

    @property
    def dynamodb_resource(self):
        return self._resource("dynamodb")

    @property
    def s3_client(self):
        return self._client("s3")

    @property
    def sqs_client(self):
        return self._client("sqs")

    @property
    def stepfunctions_client(self):
        return self._client("stepfunctions")

    @property
    def iam_client(self):
        return self._client("iam")

    @property
    def cloudformation_client(self):
        return self._client("cloudformation")

    @property
    def ecs_client(self):
        return self._client("ecs")

    @property
    def ecr_client(self):
        return self._client("ecr")

    @property
    def apigateway_client(self):
        return self._client("apigateway")

    @property
    def apigatewayv2_client(self):
        return self._client("apigatewayv2")

    @property
    def acm_client(self):
        return self._client("acm")

    @property
    def route53_client(self):
        return self._client("route53")

    @property
    def cloudfront_client(self):
        return self._client("cloudfront")


@pytest.fixture(scope="session")
def aws_clients() -> AWSClients:
    """Provides AWS clients configured for LocalStack."""
    return AWSClients(endpoint_url=LOCALSTACK_ENDPOINT, region=AWS_REGION)


# =============================================================================
# Wait/Polling Utilities
# =============================================================================

class WaitFor:
    """Polling utilities with retry logic using tenacity."""

    def __init__(self, clients: AWSClients):
        self.clients = clients

    @retry(wait=wait_fixed(2), stop=stop_after_delay(60), reraise=True)
    def lambda_active(self, function_name: str) -> dict:
        """Wait for Lambda function to be Active."""
        response = self.clients.lambda_client.get_function(FunctionName=function_name)
        state = response["Configuration"]["State"]
        if state != "Active":
            raise Exception(f"Lambda {function_name} state is {state}")
        return response

    @retry(wait=wait_fixed(2), stop=stop_after_delay(120), reraise=True)
    def sfn_execution_complete(self, execution_arn: str) -> dict:
        """Wait for Step Functions execution to complete."""
        response = self.clients.stepfunctions_client.describe_execution(
            executionArn=execution_arn
        )
        status = response["status"]
        if status not in ("SUCCEEDED", "FAILED", "TIMED_OUT", "ABORTED"):
            raise Exception(f"Execution status is {status}")
        return response

    @retry(wait=wait_fixed(2), stop=stop_after_delay(60), reraise=True)
    def url_responds(self, url: str, expected_status: int = 200) -> requests.Response:
        """Wait for URL to respond with expected status."""
        response = requests.get(url, timeout=10)
        if response.status_code != expected_status:
            raise Exception(f"URL returned {response.status_code}")
        return response

    @retry(wait=wait_fixed(1), stop=stop_after_delay(30), reraise=True)
    def localstack_ready(self) -> dict:
        """Wait for LocalStack to be ready."""
        response = requests.get(
            f"{self.clients.endpoint_url}/_localstack/health", timeout=5
        )
        data = response.json()
        if "services" not in data:
            raise Exception("LocalStack not ready")
        return data

    @retry(wait=wait_fixed(2), stop=stop_after_delay(120), reraise=True)
    def ecs_service_running(self, cluster: str, service: str) -> dict:
        """Wait for ECS service to have running tasks."""
        response = self.clients.ecs_client.describe_services(
            cluster=cluster, services=[service]
        )
        if not response["services"]:
            raise Exception(f"Service {service} not found")
        svc = response["services"][0]
        if svc["runningCount"] < 1:
            raise Exception(f"Service has {svc['runningCount']} running tasks")
        return response


@pytest.fixture(scope="session")
def wait_for(aws_clients: AWSClients) -> WaitFor:
    """Provides polling utilities."""
    return WaitFor(aws_clients)


# =============================================================================
# Environment Loading
# =============================================================================

def load_env_file(env_path: Path) -> dict:
    """Load environment variables from a .env file."""
    env = {}
    if env_path.exists():
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, _, value = line.partition("=")
                    env[key.strip()] = value.strip()
    return env


# =============================================================================
# Deployment Helpers
# =============================================================================

def get_sample_dir(sample_name: str, language: str) -> Path:
    """Get the path to a sample directory."""
    return SAMPLES_DIR / sample_name / language


def get_deploy_script_path(sample_name: str, language: str, iac_method: str) -> Path:
    """Get the path to the deploy script for a sample/iac combination."""
    sample_dir = get_sample_dir(sample_name, language)

    if iac_method == "scripts":
        return sample_dir / "scripts" / "deploy.sh"
    else:
        return sample_dir / iac_method / "deploy.sh"


def get_env_path(sample_name: str, language: str) -> Path:
    """Get the path to the .env file after deployment."""
    return get_sample_dir(sample_name, language) / "scripts" / ".env"


def run_deploy(sample_name: str, language: str, iac_method: str, timeout: int = 300) -> dict:
    """
    Run deployment and return env vars.

    Returns:
        Dict of environment variables from .env
    """
    script_path = get_deploy_script_path(sample_name, language, iac_method)

    if not script_path.exists():
        raise FileNotFoundError(f"Deploy script not found: {script_path}")

    result = subprocess.run(
        ["bash", str(script_path)],
        cwd=script_path.parent,
        capture_output=True,
        text=True,
        timeout=timeout,
    )

    if result.returncode != 0:
        raise RuntimeError(
            f"Deployment failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )

    env_path = get_env_path(sample_name, language)
    return load_env_file(env_path)


# =============================================================================
# Lambda Invocation Helper
# =============================================================================

@pytest.fixture
def invoke_lambda(aws_clients: AWSClients):
    """Returns a function to invoke Lambda and parse response."""

    def _invoke(function_name: str, payload: dict) -> dict:
        response = aws_clients.lambda_client.invoke(
            FunctionName=function_name,
            Payload=json.dumps(payload),
        )
        return json.loads(response["Payload"].read())

    return _invoke


# =============================================================================
# LocalStack Health Check
# =============================================================================

@pytest.fixture(scope="session", autouse=True)
def ensure_localstack_ready(wait_for: WaitFor):
    """Ensure LocalStack is ready before running tests."""
    try:
        wait_for.localstack_ready()
    except Exception as e:
        pytest.exit(f"LocalStack is not available: {e}")
