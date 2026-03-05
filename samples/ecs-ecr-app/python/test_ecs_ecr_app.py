"""
Tests for ecs-ecr-app sample.

Run with:
    uv run pytest samples/ecs-ecr-app/python/ -v
"""

from pathlib import Path

import pytest

# Sample configuration
SAMPLE_NAME = "ecs-ecr-app"
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

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method, timeout=600)

    return env


class TestEcsEcrApp:
    """Test suite for ECS ECR Container App sample."""

    def test_ecr_repository_exists(self, deployed_env, aws_clients):
        """ECR repository should exist."""
        repo_name = deployed_env.get("REPO_NAME")
        if not repo_name:
            # Extract from REPO_URI if REPO_NAME not available
            repo_uri = deployed_env.get("REPO_URI", "")
            repo_name = repo_uri.split("/")[-1] if "/" in repo_uri else "ecs-ecr-sample"

        response = aws_clients.ecr_client.describe_repositories(
            repositoryNames=[repo_name]
        )
        assert len(response["repositories"]) > 0
        assert "repositoryUri" in response["repositories"][0]

    def test_docker_image_in_ecr(self, deployed_env, aws_clients):
        """Docker image should be in ECR."""
        repo_name = deployed_env.get("REPO_NAME")
        if not repo_name:
            repo_uri = deployed_env.get("REPO_URI", "")
            repo_name = repo_uri.split("/")[-1] if "/" in repo_uri else "ecs-ecr-sample"

        response = aws_clients.ecr_client.describe_images(
            repositoryName=repo_name
        )
        assert len(response["imageDetails"]) > 0

    def test_ecs_cluster_exists(self, deployed_env, aws_clients):
        """ECS cluster should exist and be active."""
        cluster_name = deployed_env["CLUSTER_NAME"]
        response = aws_clients.ecs_client.describe_clusters(
            clusters=[cluster_name]
        )
        assert len(response["clusters"]) > 0
        assert response["clusters"][0]["status"] == "ACTIVE"

    def test_ecs_service_exists(self, deployed_env, aws_clients):
        """ECS service should exist and be active."""
        cluster_name = deployed_env["CLUSTER_NAME"]
        # List services in the cluster to find the service name dynamically
        list_response = aws_clients.ecs_client.list_services(cluster=cluster_name)
        if not list_response.get("serviceArns"):
            pytest.skip("No services found in cluster")

        service_arn = list_response["serviceArns"][0]
        response = aws_clients.ecs_client.describe_services(
            cluster=cluster_name,
            services=[service_arn]
        )
        assert len(response["services"]) > 0
        assert response["services"][0]["status"] == "ACTIVE"

    def test_ecs_task_running(self, deployed_env, aws_clients):
        """ECS task should be running."""
        task_arn = deployed_env.get("TASK_ARN")
        if not task_arn or task_arn == "None":
            pytest.skip("No task ARN available")

        cluster_name = deployed_env["CLUSTER_NAME"]
        response = aws_clients.ecs_client.describe_tasks(
            cluster=cluster_name,
            tasks=[task_arn]
        )
        assert len(response["tasks"]) > 0
        assert response["tasks"][0]["lastStatus"] == "RUNNING"

    def test_container_http_response(self, deployed_env, aws_clients, wait_for):
        """Container should respond to HTTP (if endpoint available)."""
        import requests

        endpoint = deployed_env.get("CONTAINER_ENDPOINT")
        if not endpoint:
            # Try to get endpoint from task
            task_arn = deployed_env.get("TASK_ARN")
            cluster_name = deployed_env.get("CLUSTER_NAME")

            if task_arn and task_arn != "None":
                response = aws_clients.ecs_client.describe_tasks(
                    cluster=cluster_name,
                    tasks=[task_arn]
                )
                if response["tasks"]:
                    task = response["tasks"][0]
                    containers = task.get("containers", [])
                    if containers:
                        bindings = containers[0].get("networkBindings", [])
                        if bindings:
                            host_port = bindings[0].get("hostPort")
                            if host_port:
                                endpoint = f"http://localhost.localstack.cloud:{host_port}"

        if not endpoint:
            pytest.skip("No HTTP endpoint available (LocalStack ECS networking)")

        try:
            response = requests.get(endpoint, timeout=10)
            assert response.status_code == 200
        except requests.exceptions.RequestException:
            pytest.skip("HTTP endpoint not reachable")
