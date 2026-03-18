"""
Tests for Reproducible ML sample.

Run all IaC methods:
    uv run pytest samples/reproducible-ml/python/ -v

Run specific IaC method:
    uv run pytest samples/reproducible-ml/python/ -v -k scripts
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

SAMPLE_NAME = "reproducible-ml"
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


class TestReproducibleMl:
    """Test ML training and inference pipeline."""

    def test_s3_bucket_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the S3 bucket was created."""
        bucket = deployed_env.get("S3_BUCKET")
        assert bucket, "S3_BUCKET should be set"

        response = aws_clients.s3_client.head_bucket(Bucket=bucket)
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    def test_training_data_uploaded(self, deployed_env, aws_clients: AWSClients):
        """Test that training data was uploaded to S3."""
        bucket = deployed_env.get("S3_BUCKET")

        response = aws_clients.s3_client.head_object(
            Bucket=bucket, Key="digits.csv.gz"
        )
        assert response["ContentLength"] > 0

    def test_train_function_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the training Lambda function exists."""
        fn_name = deployed_env.get("TRAIN_FUNCTION")
        assert fn_name, "TRAIN_FUNCTION should be set"

        response = aws_clients.lambda_client.get_function(FunctionName=fn_name)
        assert response["Configuration"]["FunctionName"] == fn_name

    def test_predict_function_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the prediction Lambda function exists."""
        fn_name = deployed_env.get("PREDICT_FUNCTION")
        assert fn_name, "PREDICT_FUNCTION should be set"

        response = aws_clients.lambda_client.get_function(FunctionName=fn_name)
        assert response["Configuration"]["FunctionName"] == fn_name

    def test_train_function_has_sklearn_layer(self, deployed_env, aws_clients: AWSClients):
        """Test that the training function has the scikit-learn layer."""
        fn_name = deployed_env.get("TRAIN_FUNCTION")

        response = aws_clients.lambda_client.get_function(FunctionName=fn_name)
        layers = response["Configuration"].get("Layers", [])
        layer_arns = [l["Arn"] for l in layers]
        assert any("scikit-learn" in arn for arn in layer_arns), \
            f"Expected scikit-learn layer, got: {layer_arns}"

    def test_model_saved_to_s3(self, deployed_env, aws_clients: AWSClients):
        """Test that the trained model was saved to S3."""
        bucket = deployed_env.get("S3_BUCKET")

        response = aws_clients.s3_client.head_object(
            Bucket=bucket, Key="model.joblib"
        )
        assert response["ContentLength"] > 0

    def test_test_set_saved_to_s3(self, deployed_env, aws_clients: AWSClients):
        """Test that the test set was saved to S3."""
        bucket = deployed_env.get("S3_BUCKET")

        response = aws_clients.s3_client.head_object(
            Bucket=bucket, Key="test-set.npy"
        )
        assert response["ContentLength"] > 0

    def test_train_function_invocable(self, deployed_env, aws_clients: AWSClients):
        """Test that the training function can be invoked."""
        fn_name = deployed_env.get("TRAIN_FUNCTION")

        response = aws_clients.lambda_client.invoke(
            FunctionName=fn_name,
        )
        payload = json.loads(response["Payload"].read())
        assert payload.get("status") == "trained"
        assert payload.get("samples") > 0

    def test_predict_function_invocable(self, deployed_env, aws_clients: AWSClients):
        """Test that the prediction function can be invoked."""
        fn_name = deployed_env.get("PREDICT_FUNCTION")

        response = aws_clients.lambda_client.invoke(
            FunctionName=fn_name,
        )
        payload = json.loads(response["Payload"].read())
        assert payload.get("predictions_count") > 0
        assert len(payload.get("first_10", [])) == 10

    def test_predictions_are_digits(self, deployed_env, aws_clients: AWSClients):
        """Test that predictions are valid digit values (0-9)."""
        fn_name = deployed_env.get("PREDICT_FUNCTION")

        response = aws_clients.lambda_client.invoke(
            FunctionName=fn_name,
        )
        payload = json.loads(response["Payload"].read())
        for digit in payload.get("first_10", []):
            assert 0 <= digit <= 9, f"Predicted digit {digit} out of range"
