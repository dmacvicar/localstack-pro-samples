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

LOCALSTACK_ENDPOINT = os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost.localstack.cloud:4566")
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

    @property
    def athena_client(self):
        return self._client("athena")

    @property
    def glue_client(self):
        return self._client("glue")

    @property
    def mq_client(self):
        return self._client("mq")

    @property
    def iot_client(self):
        return self._client("iot")

    @property
    def codecommit_client(self):
        return self._client("codecommit")

    @property
    def transfer_client(self):
        return self._client("transfer")

    @property
    def glacier_client(self):
        return self._client("glacier")

    @property
    def rds_client(self):
        return self._client("rds")

    @property
    def rds_data_client(self):
        return self._client("rds-data")

    @property
    def secretsmanager_client(self):
        return self._client("secretsmanager")

    @property
    def appsync_client(self):
        return self._client("appsync")

    @property
    def redshift_client(self):
        return self._client("redshift")

    @property
    def redshift_data_client(self):
        return self._client("redshift-data")

    @property
    def kafka_client(self):
        return self._client("kafka")

    @property
    def emr_serverless_client(self):
        return self._client("emr-serverless")


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

    @retry(wait=wait_fixed(4), stop=stop_after_delay(180), reraise=True)
    def glue_job_complete(self, job_name: str, run_id: str) -> dict:
        """Wait for Glue job run to complete."""
        response = self.clients.glue_client.get_job_run(
            JobName=job_name, RunId=run_id
        )
        state = response["JobRun"]["JobRunState"]
        if state in ("STARTING", "RUNNING", "STOPPING"):
            raise Exception(f"Glue job {job_name} run {run_id} state is {state}")
        return response

    @retry(wait=wait_fixed(3), stop=stop_after_delay(180), reraise=True)
    def athena_query_complete(self, query_execution_id: str) -> dict:
        """Wait for Athena query to complete."""
        response = self.clients.athena_client.get_query_execution(
            QueryExecutionId=query_execution_id
        )
        state = response["QueryExecution"]["Status"]["State"]
        if state in ("QUEUED", "RUNNING"):
            raise Exception(f"Query {query_execution_id} state is {state}")
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

    # Pass AWS credentials to subprocess
    env = os.environ.copy()
    env.update({
        "AWS_ACCESS_KEY_ID": AWS_ACCESS_KEY_ID,
        "AWS_SECRET_ACCESS_KEY": AWS_SECRET_ACCESS_KEY,
        "AWS_DEFAULT_REGION": AWS_REGION,
    })

    result = subprocess.run(
        ["bash", str(script_path)],
        cwd=script_path.parent,
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
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
# Shared Test Fixtures (for tests that work across languages)
# =============================================================================

def discover_languages(sample_name: str) -> list[str]:
    """Discover available languages for a sample."""
    sample_parent = SAMPLES_DIR / sample_name
    languages = []
    for lang_dir in sample_parent.iterdir():
        if lang_dir.is_dir() and not lang_dir.name.startswith((".", "_")):
            # Check if it has any deploy scripts
            has_scripts = (lang_dir / "scripts" / "deploy.sh").exists()
            has_iac = any((lang_dir / iac / "deploy.sh").exists()
                         for iac in ["terraform", "cloudformation", "cdk"])
            if has_scripts or has_iac:
                languages.append(lang_dir.name)
    return sorted(languages)


def discover_iac_methods(sample_name: str, language: str) -> list[str]:
    """Discover available IaC methods for a sample."""
    sample_dir = get_sample_dir(sample_name, language)
    methods = []
    if (sample_dir / "scripts" / "deploy.sh").exists():
        methods.append("scripts")
    for iac in ["terraform", "cloudformation", "cdk"]:
        if (sample_dir / iac / "deploy.sh").exists():
            methods.append(iac)
    return methods


def discover_all_variants(sample_name: str) -> list[tuple[str, str]]:
    """Discover all (language, iac_method) combinations for a sample."""
    variants = []
    for lang in discover_languages(sample_name):
        for iac in discover_iac_methods(sample_name, lang):
            variants.append((lang, iac))
    return variants


def pytest_generate_tests(metafunc):
    """Dynamically parameterize shared tests by language and IaC method.

    For shared tests (in samples/<sample>/test_*.py) that use the
    `deployed_env` fixture, this discovers all language × IaC combinations
    and parameterizes accordingly.

    Use -k to filter: pytest samples/my-sample/ -k "javascript and scripts"
    """
    if "deployed_env" in metafunc.fixturenames:
        # Check if this is a shared test (in sample parent dir, not language dir)
        test_path = Path(metafunc.module.__file__)
        sample_dir = test_path.parent

        # If test is directly under samples/<sample>/, it's a shared test
        if sample_dir.parent == SAMPLES_DIR:
            sample_name = sample_dir.name
            variants = discover_all_variants(sample_name)

            if variants:
                # Parameterize with language-iac format for -k filtering
                ids = [f"{lang}-{iac}" for lang, iac in variants]
                metafunc.parametrize(
                    "deployed_env",
                    variants,
                    ids=ids,
                    indirect=True,
                    scope="module"
                )


@pytest.fixture(scope="module")
def deployed_env(request, wait_for: WaitFor) -> dict:
    """Deploy the sample and return environment variables.

    For shared tests, this receives (language, iac_method) from parametrize.
    For language-specific tests, they define their own fixture.
    """
    # Get parameters - either from parametrize or skip
    if not hasattr(request, "param"):
        pytest.skip("deployed_env requires parametrization (use shared test pattern)")

    language, iac_method = request.param

    # Determine sample name from test file location
    test_path = Path(request.module.__file__)
    sample_name = test_path.parent.name

    script_path = get_deploy_script_path(sample_name, language, iac_method)
    if not script_path.exists():
        pytest.skip(f"Deploy script not found: {script_path}")

    env = run_deploy(sample_name, language, iac_method)

    # Wait for Lambda to be active if function name is in env
    if "FUNCTION_NAME" in env:
        wait_for.lambda_active(env["FUNCTION_NAME"])

    return env


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
