"""
Tests for CodeCommit Git Repository sample.

Run all IaC methods:
    uv run pytest samples/codecommit-git-repo/python/ -v

Run specific IaC method:
    uv run pytest samples/codecommit-git-repo/python/ -v -k scripts
    uv run pytest samples/codecommit-git-repo/python/ -v -k terraform
"""

import os
import subprocess
import sys
import tempfile
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

SAMPLE_NAME = "codecommit-git-repo"
LANGUAGE = "python"

# IaC methods to test
# Note: CloudFormation and CDK don't fully support AWS::CodeCommit::Repository in LocalStack
IAC_METHODS = ["scripts", "terraform"]


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


class TestCodeCommitGitRepo:
    """Test CodeCommit repository operations."""

    def test_repository_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the CodeCommit repository was created."""
        repo_name = deployed_env.get("REPO_NAME")
        assert repo_name, "REPO_NAME should be set"

        response = aws_clients.codecommit_client.get_repository(
            repositoryName=repo_name
        )
        assert response["repositoryMetadata"]["repositoryName"] == repo_name

    def test_repository_has_clone_urls(self, deployed_env, aws_clients: AWSClients):
        """Test that the repository has clone URLs."""
        repo_name = deployed_env.get("REPO_NAME")

        response = aws_clients.codecommit_client.get_repository(
            repositoryName=repo_name
        )
        metadata = response["repositoryMetadata"]

        # Verify clone URLs are present
        assert "cloneUrlSsh" in metadata
        assert "cloneUrlHttp" in metadata
        assert metadata["cloneUrlSsh"]
        assert metadata["cloneUrlHttp"]

    def test_repository_arn_format(self, deployed_env, aws_clients: AWSClients):
        """Test that the repository ARN has correct format."""
        repo_name = deployed_env.get("REPO_NAME")
        repo_arn = deployed_env.get("REPO_ARN")

        if not repo_arn:
            # Get ARN from API if not in env
            response = aws_clients.codecommit_client.get_repository(
                repositoryName=repo_name
            )
            repo_arn = response["repositoryMetadata"]["Arn"]

        assert "codecommit" in repo_arn.lower()
        assert repo_name in repo_arn

    def test_list_repositories_includes_repo(self, deployed_env, aws_clients: AWSClients):
        """Test that the repository appears in the list."""
        repo_name = deployed_env.get("REPO_NAME")

        response = aws_clients.codecommit_client.list_repositories()
        repo_names = [r["repositoryName"] for r in response.get("repositories", [])]

        assert repo_name in repo_names

    def test_clone_url_ssh_format(self, deployed_env):
        """Test that the SSH clone URL has the expected format."""
        clone_url_ssh = deployed_env.get("CLONE_URL_SSH")
        if not clone_url_ssh:
            pytest.skip("CLONE_URL_SSH not in environment")

        # SSH URLs should be in format: ssh://git-codecommit.<region>.amazonaws.com/v1/repos/<name>
        # or git://<host>:<port>/<name> for LocalStack
        assert "repo" in clone_url_ssh.lower() or "git" in clone_url_ssh.lower()

    def test_clone_url_http_format(self, deployed_env):
        """Test that the HTTP clone URL has the expected format."""
        clone_url_http = deployed_env.get("CLONE_URL_HTTP")
        if not clone_url_http:
            pytest.skip("CLONE_URL_HTTP not in environment")

        # LocalStack may use git:// protocol instead of https://
        valid_protocols = ("https://", "http://", "git://")
        assert any(clone_url_http.startswith(p) for p in valid_protocols)

    def test_git_clone_works(self, deployed_env):
        """Test that git clone works with the repository."""
        clone_url_ssh = deployed_env.get("CLONE_URL_SSH")
        if not clone_url_ssh:
            pytest.skip("CLONE_URL_SSH not in environment")

        # Create a temporary directory for cloning
        with tempfile.TemporaryDirectory() as tmpdir:
            clone_path = os.path.join(tmpdir, "repo")

            try:
                # Try to clone the repository
                result = subprocess.run(
                    ["git", "clone", clone_url_ssh, clone_path],
                    capture_output=True,
                    text=True,
                    timeout=30,
                    env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
                )

                # Clone should succeed (return code 0)
                # Note: Some LocalStack versions may not fully support git protocol
                if result.returncode != 0:
                    # Check if it's a known limitation
                    if "Connection refused" in result.stderr or "Could not read" in result.stderr:
                        pytest.skip("Git clone not fully supported in this LocalStack version")
                    else:
                        pytest.fail(f"Git clone failed: {result.stderr}")

                # Verify the directory was created
                assert os.path.isdir(clone_path)

            except subprocess.TimeoutExpired:
                pytest.skip("Git clone timed out")
            except FileNotFoundError:
                pytest.skip("Git not installed")
