"""
Tests for SageMaker Inference sample.

Run all IaC methods:
    uv run pytest samples/sagemaker-inference/python/ -v

Run specific IaC method:
    uv run pytest samples/sagemaker-inference/python/ -v -k scripts
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

SAMPLE_NAME = "sagemaker-inference"
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


class TestSagemakerInference:
    """Test SageMaker model, endpoint config, endpoint, and inference."""

    def test_s3_bucket_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the S3 bucket was created."""
        bucket = deployed_env.get("S3_BUCKET")
        assert bucket, "S3_BUCKET should be set"

        response = aws_clients.s3_client.head_bucket(Bucket=bucket)
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    def test_model_uploaded_to_s3(self, deployed_env, aws_clients: AWSClients):
        """Test that the model was uploaded to S3."""
        bucket = deployed_env.get("S3_BUCKET")

        response = aws_clients.s3_client.head_object(
            Bucket=bucket, Key="model.tar.gz"
        )
        assert response["ContentLength"] > 0

    def test_model_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the SageMaker model was created."""
        model_name = deployed_env.get("MODEL_NAME")
        assert model_name, "MODEL_NAME should be set"

        response = aws_clients.sagemaker_client.describe_model(
            ModelName=model_name
        )
        assert response["ModelName"] == model_name

    def test_model_has_container(self, deployed_env, aws_clients: AWSClients):
        """Test that the model has the correct container image."""
        model_name = deployed_env.get("MODEL_NAME")

        response = aws_clients.sagemaker_client.describe_model(
            ModelName=model_name
        )
        container = response["PrimaryContainer"]
        assert "pytorch-inference" in container["Image"]

    def test_endpoint_config_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the endpoint config was created."""
        config_name = deployed_env.get("CONFIG_NAME")
        assert config_name, "CONFIG_NAME should be set"

        response = aws_clients.sagemaker_client.describe_endpoint_config(
            EndpointConfigName=config_name
        )
        assert response["EndpointConfigName"] == config_name

    def test_endpoint_config_has_variant(self, deployed_env, aws_clients: AWSClients):
        """Test that the endpoint config has a production variant."""
        config_name = deployed_env.get("CONFIG_NAME")

        response = aws_clients.sagemaker_client.describe_endpoint_config(
            EndpointConfigName=config_name
        )
        variants = response["ProductionVariants"]
        assert len(variants) >= 1
        assert variants[0]["ModelName"] == deployed_env["MODEL_NAME"]

    def test_endpoint_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the endpoint was created."""
        endpoint_name = deployed_env.get("ENDPOINT_NAME")
        assert endpoint_name, "ENDPOINT_NAME should be set"

        response = aws_clients.sagemaker_client.describe_endpoint(
            EndpointName=endpoint_name
        )
        assert response["EndpointName"] == endpoint_name

    def test_endpoint_in_service(self, deployed_env, aws_clients: AWSClients):
        """Test that the endpoint is InService."""
        endpoint_name = deployed_env.get("ENDPOINT_NAME")

        response = aws_clients.sagemaker_client.describe_endpoint(
            EndpointName=endpoint_name
        )
        assert response["EndpointStatus"] == "InService"

    def test_endpoint_invoke(self, deployed_env, aws_clients: AWSClients):
        """Test that the endpoint can be invoked."""
        endpoint_name = deployed_env.get("ENDPOINT_NAME")

        # Simple test input
        test_input = {"inputs": [[[0.0] * 28] * 28]}

        response = aws_clients.sagemaker_runtime_client.invoke_endpoint(
            EndpointName=endpoint_name,
            Body=json.dumps(test_input),
            ContentType="application/json",
            Accept="application/json",
        )
        body = json.loads(response["Body"].read().decode("utf-8"))
        assert isinstance(body, list), f"Expected list response, got {type(body)}"

    def test_endpoint_config_name_matches(self, deployed_env, aws_clients: AWSClients):
        """Test that the endpoint references the correct config."""
        endpoint_name = deployed_env.get("ENDPOINT_NAME")
        config_name = deployed_env.get("CONFIG_NAME")

        response = aws_clients.sagemaker_client.describe_endpoint(
            EndpointName=endpoint_name
        )
        assert response["EndpointConfigName"] == config_name
