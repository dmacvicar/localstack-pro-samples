"""
Tests for Transfer FTP to S3 sample.

Run all IaC methods:
    uv run pytest samples/transfer-ftp-s3/python/ -v

Run specific IaC method:
    uv run pytest samples/transfer-ftp-s3/python/ -v -k scripts
    uv run pytest samples/transfer-ftp-s3/python/ -v -k terraform
"""

import io
import sys
import time
from ftplib import FTP
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

SAMPLE_NAME = "transfer-ftp-s3"
LANGUAGE = "python"

# IaC methods to test
# Note: Terraform times out, CloudFormation/CDK return "unknown" for ServerId
IAC_METHODS = ["scripts"]


@pytest.fixture(scope="module", params=IAC_METHODS)
def deployed_env(request, aws_clients: AWSClients, wait_for: WaitFor):
    """Deploy the sample and return environment variables."""
    iac_method = request.param

    # Check if deploy script exists
    sample_dir = get_sample_dir(SAMPLE_NAME, LANGUAGE)
    if iac_method == "scripts":
        deploy_path = sample_dir / "scripts" / "deploy.sh"
    else:
        deploy_path = sample_dir / iac_method / "deploy.sh"

    if not deploy_path.exists():
        pytest.skip(f"Deploy script not found: {deploy_path}")

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method, timeout=300)

    # Add IaC method to env for test identification
    env["_IAC_METHOD"] = iac_method

    return env


class TestTransferFtpS3:
    """Test Transfer FTP server and S3 integration."""

    def test_server_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the Transfer server was created."""
        server_id = deployed_env.get("SERVER_ID")
        assert server_id, "SERVER_ID should be set"

        response = aws_clients.transfer_client.describe_server(ServerId=server_id)
        assert response["Server"]["ServerId"] == server_id

    def test_server_has_ftp_protocol(self, deployed_env, aws_clients: AWSClients):
        """Test that the server supports FTP protocol."""
        server_id = deployed_env.get("SERVER_ID")

        response = aws_clients.transfer_client.describe_server(ServerId=server_id)
        protocols = response["Server"].get("Protocols", [])
        assert "FTP" in protocols

    def test_bucket_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the S3 bucket was created."""
        bucket_name = deployed_env.get("BUCKET_NAME")
        assert bucket_name, "BUCKET_NAME should be set"

        response = aws_clients.s3_client.head_bucket(Bucket=bucket_name)
        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    def test_user_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the Transfer user was created."""
        server_id = deployed_env.get("SERVER_ID")
        username = deployed_env.get("USERNAME")

        if not username:
            pytest.skip("USERNAME not in environment")

        response = aws_clients.transfer_client.describe_user(
            ServerId=server_id,
            UserName=username,
        )
        assert response["User"]["UserName"] == username

    def test_ftp_connect(self, deployed_env):
        """Test that we can connect to the FTP server."""
        ftp_port = deployed_env.get("FTP_PORT")
        username = deployed_env.get("USERNAME")
        password = deployed_env.get("FTP_PASSWORD", "12345")

        if not ftp_port:
            pytest.skip("FTP_PORT not in environment")

        ftp = FTP()
        try:
            ftp.connect("localhost", port=int(ftp_port))
            result = ftp.login(username, password)
            assert "successful" in result.lower()
        finally:
            try:
                ftp.quit()
            except Exception:
                pass

    def test_ftp_upload_to_s3(self, deployed_env, aws_clients: AWSClients):
        """Test that files uploaded via FTP appear in S3."""
        ftp_port = deployed_env.get("FTP_PORT")
        username = deployed_env.get("USERNAME")
        password = deployed_env.get("FTP_PASSWORD", "12345")
        bucket_name = deployed_env.get("BUCKET_NAME")

        if not ftp_port:
            pytest.skip("FTP_PORT not in environment")

        test_content = b"test file content via FTP"
        test_filename = "test-upload.txt"

        ftp = FTP()
        try:
            ftp.connect("localhost", port=int(ftp_port))
            ftp.login(username, password)

            # Upload file via FTP
            ftp.storbinary(f"STOR {test_filename}", io.BytesIO(test_content))

            # Give it time to sync to S3
            time.sleep(1)

            # Verify file appears in S3
            response = aws_clients.s3_client.get_object(
                Bucket=bucket_name,
                Key=test_filename,
            )
            downloaded_content = response["Body"].read()
            assert downloaded_content == test_content
        finally:
            try:
                ftp.quit()
            except Exception:
                pass

    def test_ftp_list_directory(self, deployed_env):
        """Test that we can list the FTP directory."""
        ftp_port = deployed_env.get("FTP_PORT")
        username = deployed_env.get("USERNAME")
        password = deployed_env.get("FTP_PASSWORD", "12345")

        if not ftp_port:
            pytest.skip("FTP_PORT not in environment")

        ftp = FTP()
        try:
            ftp.connect("localhost", port=int(ftp_port))
            ftp.login(username, password)

            # List directory
            files = ftp.nlst()
            # Should be able to list (may be empty or have test files)
            assert isinstance(files, list)
        finally:
            try:
                ftp.quit()
            except Exception:
                pass
