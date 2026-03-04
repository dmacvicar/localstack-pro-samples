"""
Tests for lambda-s3-http sample (Gaming Scoreboard).

Run with:
    uv run pytest samples/lambda-s3-http/python/ -v
"""

import json
from pathlib import Path

import pytest

# Sample configuration
SAMPLE_NAME = "lambda-s3-http"
LANGUAGE = "python"
SAMPLE_DIR = Path(__file__).parent


def get_iac_methods():
    """Discover available IaC methods for this sample."""
    methods = []
    if (SAMPLE_DIR / "scripts" / "deploy.sh").exists():
        methods.append("scripts")
    for iac in ["terraform", "cloudformation", "cdk"]:
        if (SAMPLE_DIR / iac / "deploy.sh").exists():
            methods.append(iac)
    return methods


@pytest.fixture(scope="module", params=get_iac_methods())
def deployed_env(request, wait_for):
    """Deploy the sample with each IaC method and return env vars."""
    from conftest import run_deploy, get_deploy_script_path

    iac_method = request.param

    script_path = get_deploy_script_path(SAMPLE_NAME, LANGUAGE, iac_method)
    if not script_path.exists():
        pytest.skip(f"Deploy script not found for {iac_method}")

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method)

    # Wait for Lambda functions to be active
    for func_key in ["HTTP_FUNCTION", "S3_FUNCTION", "SQS_FUNCTION"]:
        if func_key in env:
            wait_for.lambda_active(env[func_key])

    return env


class TestLambdaS3Http:
    """Test suite for Lambda S3 HTTP sample."""

    def test_http_function_exists(self, deployed_env, aws_clients):
        """HTTP Lambda function should exist and be active."""
        function_name = deployed_env["HTTP_FUNCTION"]
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_s3_function_exists(self, deployed_env, aws_clients):
        """S3 Lambda function should exist and be active."""
        function_name = deployed_env["S3_FUNCTION"]
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_sqs_function_exists(self, deployed_env, aws_clients):
        """SQS Lambda function should exist and be active."""
        function_name = deployed_env["SQS_FUNCTION"]
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_dynamodb_table_exists(self, deployed_env, aws_clients):
        """DynamoDB table should exist."""
        table_name = deployed_env["TABLE_NAME"]
        response = aws_clients.dynamodb_client.describe_table(TableName=table_name)
        assert response["Table"]["TableStatus"] == "ACTIVE"

    def test_s3_bucket_exists(self, deployed_env, aws_clients):
        """S3 bucket should exist."""
        bucket_name = deployed_env["BUCKET_NAME"]
        response = aws_clients.s3_client.head_bucket(Bucket=bucket_name)
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    def test_sqs_queue_exists(self, deployed_env, aws_clients):
        """SQS queue should exist."""
        queue_name = deployed_env["QUEUE_NAME"]
        response = aws_clients.sqs_client.get_queue_url(QueueName=queue_name)
        assert "QueueUrl" in response

    def test_submit_score(self, deployed_env, invoke_lambda):
        """Should submit a score."""
        function_name = deployed_env["HTTP_FUNCTION"]

        response = invoke_lambda(function_name, {
            "httpMethod": "POST",
            "path": "/scores",
            "body": json.dumps({
                "playerId": "test-player-1",
                "score": 1500,
                "game": "space-invaders"
            })
        })

        assert response["statusCode"] == 201
        body = json.loads(response["body"])
        assert body["message"] == "Score submitted"
        assert body["item"]["playerId"] == "test-player-1"

    def test_get_scores(self, deployed_env, invoke_lambda):
        """Should get top scores."""
        function_name = deployed_env["HTTP_FUNCTION"]

        # Submit a score first
        invoke_lambda(function_name, {
            "httpMethod": "POST",
            "path": "/scores",
            "body": json.dumps({
                "playerId": "test-player-2",
                "score": 2000,
                "game": "space-invaders"
            })
        })

        # Get scores
        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/scores"
        })

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert "scores" in body

    def test_get_player_scores(self, deployed_env, invoke_lambda):
        """Should get scores for a specific player."""
        function_name = deployed_env["HTTP_FUNCTION"]

        # Submit a score
        invoke_lambda(function_name, {
            "httpMethod": "POST",
            "path": "/scores",
            "body": json.dumps({
                "playerId": "test-player-3",
                "score": 2500,
                "game": "tetris"
            })
        })

        # Get player scores
        response = invoke_lambda(function_name, {
            "httpMethod": "GET",
            "path": "/scores/test-player-3",
            "pathParameters": {"playerId": "test-player-3"}
        })

        assert response["statusCode"] == 200

    def test_s3_upload_triggers_lambda(self, deployed_env, aws_clients):
        """S3 upload should be possible (trigger is async)."""
        bucket_name = deployed_env["BUCKET_NAME"]

        # Upload a file
        aws_clients.s3_client.put_object(
            Bucket=bucket_name,
            Key="player1/game1.dat",
            Body=b"replay data",
            Metadata={
                "player-id": "player1",
                "game": "space-invaders"
            }
        )

        # Verify upload
        response = aws_clients.s3_client.head_object(
            Bucket=bucket_name,
            Key="player1/game1.dat"
        )
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200
