"""
Tests for EMR Serverless Spark sample.

Run all IaC methods:
    uv run pytest samples/emr-serverless-spark/java/ -v

Run specific IaC method:
    uv run pytest samples/emr-serverless-spark/java/ -v -k scripts
"""

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

SAMPLE_NAME = "emr-serverless-spark"
LANGUAGE = "java"

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


class TestEmrServerlessSpark:
    """Test EMR Serverless application, job run, S3 artifacts, and logs."""

    def test_s3_bucket_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the S3 bucket was created."""
        bucket = deployed_env.get("S3_BUCKET")
        assert bucket, "S3_BUCKET should be set"

        response = aws_clients.s3_client.head_bucket(Bucket=bucket)
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    def test_jar_uploaded_to_s3(self, deployed_env, aws_clients: AWSClients):
        """Test that the JAR was uploaded to S3."""
        bucket = deployed_env.get("S3_BUCKET")
        jar_key = deployed_env.get("JAR_S3_KEY", "code/java-spark/java-demo-1.0.jar")

        response = aws_clients.s3_client.head_object(
            Bucket=bucket, Key=jar_key
        )
        assert response["ContentLength"] > 0

    def test_application_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the EMR Serverless application was created."""
        app_id = deployed_env.get("APP_ID")
        assert app_id, "APP_ID should be set"

        response = aws_clients.emr_serverless_client.get_application(
            applicationId=app_id
        )
        assert response["application"]["name"] == deployed_env["APP_NAME"]

    def test_application_is_spark(self, deployed_env, aws_clients: AWSClients):
        """Test that the application type is SPARK."""
        app_id = deployed_env.get("APP_ID")

        response = aws_clients.emr_serverless_client.get_application(
            applicationId=app_id
        )
        assert response["application"]["type"] == "SPARK"

    def test_application_release_label(self, deployed_env, aws_clients: AWSClients):
        """Test that the application uses the correct EMR release."""
        app_id = deployed_env.get("APP_ID")

        response = aws_clients.emr_serverless_client.get_application(
            applicationId=app_id
        )
        assert response["application"]["releaseLabel"] == "emr-6.9.0"

    def test_application_started(self, deployed_env, aws_clients: AWSClients):
        """Test that the application is in STARTED state."""
        app_id = deployed_env.get("APP_ID")

        response = aws_clients.emr_serverless_client.get_application(
            applicationId=app_id
        )
        assert response["application"]["state"] == "STARTED"

    def test_job_run_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the job run was created."""
        app_id = deployed_env.get("APP_ID")
        job_run_id = deployed_env.get("JOB_RUN_ID")
        assert job_run_id, "JOB_RUN_ID should be set"

        response = aws_clients.emr_serverless_client.get_job_run(
            applicationId=app_id, jobRunId=job_run_id
        )
        assert response["jobRun"]["jobRunId"] == job_run_id

    def test_job_run_succeeded(self, deployed_env, aws_clients: AWSClients):
        """Test that the job run completed successfully."""
        app_id = deployed_env.get("APP_ID")
        job_run_id = deployed_env.get("JOB_RUN_ID")

        response = aws_clients.emr_serverless_client.get_job_run(
            applicationId=app_id, jobRunId=job_run_id
        )
        assert response["jobRun"]["state"] == "SUCCESS"

    def test_job_run_has_spark_submit(self, deployed_env, aws_clients: AWSClients):
        """Test that the job used sparkSubmit driver."""
        app_id = deployed_env.get("APP_ID")
        job_run_id = deployed_env.get("JOB_RUN_ID")

        response = aws_clients.emr_serverless_client.get_job_run(
            applicationId=app_id, jobRunId=job_run_id
        )
        job_driver = response["jobRun"]["jobDriver"]
        assert "sparkSubmit" in job_driver
        assert "java-demo-1.0.jar" in job_driver["sparkSubmit"]["entryPoint"]

    def test_logs_written_to_s3(self, deployed_env, aws_clients: AWSClients):
        """Test that job logs were written to S3."""
        bucket = deployed_env.get("S3_BUCKET")

        response = aws_clients.s3_client.list_objects_v2(
            Bucket=bucket, Prefix="logs/"
        )
        assert response.get("KeyCount", 0) > 0, "Expected log files in S3"
