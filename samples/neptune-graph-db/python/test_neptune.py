"""
Tests for Neptune Graph Database sample.

Run all IaC methods:
    uv run pytest samples/neptune-graph-db/python/ -v

Run specific IaC method:
    uv run pytest samples/neptune-graph-db/python/ -v -k scripts
"""

import subprocess
import sys
from pathlib import Path

import boto3
import pytest
from gremlin_python.driver.client import Client as GremlinClient
from gremlin_python.driver.driver_remote_connection import DriverRemoteConnection
from gremlin_python.process.anonymous_traversal import traversal

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

SAMPLE_NAME = "neptune-graph-db"
LANGUAGE = "python"

IAC_METHODS = ["scripts", "terraform", "cloudformation", "cdk"]


def neptune_client(region: str = "us-east-1"):
    """Create Neptune client."""
    return boto3.client(
        "neptune",
        endpoint_url=LOCALSTACK_ENDPOINT,
        region_name=region,
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
    )


def get_teardown_script(iac_method: str) -> Path:
    """Get teardown script path for an IaC method."""
    sample_dir = get_sample_dir(SAMPLE_NAME, LANGUAGE)
    return sample_dir / iac_method / "teardown.sh"


@pytest.fixture(scope="module", params=IAC_METHODS)
def deployed_env(request, aws_clients: AWSClients, wait_for: WaitFor):
    """Deploy the sample and return environment variables. Teardown after tests."""
    iac_method = request.param

    sample_dir = get_sample_dir(SAMPLE_NAME, LANGUAGE)
    deploy_path = sample_dir / iac_method / "deploy.sh"

    if not deploy_path.exists():
        pytest.skip(f"Deploy script not found: {deploy_path}")

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method, timeout=180)
    env["_IAC_METHOD"] = iac_method

    yield env

    # Teardown: clean up Neptune resources to free ports for next IaC method
    teardown_script = get_teardown_script(iac_method)
    if teardown_script.exists():
        import os
        run_env = os.environ.copy()
        run_env.update({
            "AWS_ACCESS_KEY_ID": AWS_ACCESS_KEY_ID,
            "AWS_SECRET_ACCESS_KEY": AWS_SECRET_ACCESS_KEY,
            "AWS_DEFAULT_REGION": "us-east-1",
        })
        subprocess.run(
            ["bash", str(teardown_script)],
            env=run_env,
            timeout=120,
            capture_output=True,
        )


class TestNeptuneGraphDb:
    """Test Neptune Graph Database functionality."""

    def test_cluster_exists(self, deployed_env):
        """Test that the Neptune cluster was created."""
        cluster_id = deployed_env.get("CLUSTER_ID")
        assert cluster_id, "CLUSTER_ID should be set"

        client = neptune_client()
        response = client.describe_db_clusters(DBClusterIdentifier=cluster_id)
        assert len(response["DBClusters"]) == 1
        assert response["DBClusters"][0]["DBClusterIdentifier"] == cluster_id

    def test_cluster_engine(self, deployed_env):
        """Test that the cluster uses Neptune engine."""
        cluster_id = deployed_env.get("CLUSTER_ID")

        client = neptune_client()
        response = client.describe_db_clusters(DBClusterIdentifier=cluster_id)
        assert response["DBClusters"][0]["Engine"] == "neptune"

    def test_cluster_is_available(self, deployed_env):
        """Test that the cluster is available."""
        cluster_id = deployed_env.get("CLUSTER_ID")

        client = neptune_client()
        response = client.describe_db_clusters(DBClusterIdentifier=cluster_id)
        assert response["DBClusters"][0]["Status"] == "available"

    def test_cluster_has_endpoint(self, deployed_env):
        """Test that the cluster has an endpoint."""
        cluster_id = deployed_env.get("CLUSTER_ID")

        client = neptune_client()
        response = client.describe_db_clusters(DBClusterIdentifier=cluster_id)
        cluster = response["DBClusters"][0]
        assert "Endpoint" in cluster or "Port" in cluster

    def test_cluster_has_port(self, deployed_env):
        """Test that the cluster has a port assigned."""
        cluster_port = deployed_env.get("CLUSTER_PORT")
        if cluster_port:
            assert int(cluster_port) > 0

    def test_cluster_arn_format(self, deployed_env):
        """Test that the cluster ARN has correct format."""
        cluster_arn = deployed_env.get("CLUSTER_ARN")
        assert cluster_arn, "CLUSTER_ARN should be set"
        assert cluster_arn.startswith("arn:aws:rds:")
        assert ":cluster:" in cluster_arn

    def test_gremlin_client_connection(self, deployed_env):
        """Test Gremlin client can connect and submit queries."""
        cluster_port = deployed_env.get("CLUSTER_PORT")
        assert cluster_port, "CLUSTER_PORT must be set for Gremlin tests"

        url = f"ws://localhost.localstack.cloud:{cluster_port}/gremlin"
        client = GremlinClient(url, "g")
        try:
            results = client.submit("[1,2,3]").all().result()
            assert results == [1, 2, 3]
        finally:
            client.close()

    def test_gremlin_add_vertices(self, deployed_env):
        """Test adding vertices to the graph via Gremlin."""
        cluster_port = deployed_env.get("CLUSTER_PORT")
        assert cluster_port, "CLUSTER_PORT must be set for Gremlin tests"

        url = f"ws://localhost.localstack.cloud:{cluster_port}/gremlin"
        client = GremlinClient(url, "g")
        try:
            # Clear graph
            client.submit("g.V().drop()").all().result()

            # Add vertices
            client.submit("g.addV('person').property('name', 'Alice')").all().result()
            client.submit("g.addV('person').property('name', 'Bob')").all().result()

            count = client.submit("g.V().count()").all().result()
            assert count == [2]

            names = sorted(client.submit("g.V().values('name')").all().result())
            assert names == ["Alice", "Bob"]
        finally:
            client.close()

    def test_gremlin_add_edges_and_traverse(self, deployed_env):
        """Test adding edges and traversing the graph."""
        cluster_port = deployed_env.get("CLUSTER_PORT")
        assert cluster_port, "CLUSTER_PORT must be set for Gremlin tests"

        url = f"ws://localhost.localstack.cloud:{cluster_port}/gremlin"
        client = GremlinClient(url, "g")
        try:
            # Clear and set up graph
            client.submit("g.V().drop()").all().result()
            client.submit("g.addV('person').property('name', 'Alice')").all().result()
            client.submit("g.addV('person').property('name', 'Bob')").all().result()

            # Add edge (use __.V() for anonymous traversal in Groovy)
            client.submit(
                "g.V().has('person','name','Alice')"
                ".addE('knows')"
                ".to(__.V().has('person','name','Bob'))"
            ).all().result()

            # Traverse the relationship
            friends = client.submit(
                "g.V().has('person','name','Alice').out('knows').values('name')"
            ).all().result()
            assert "Bob" in friends

            # Verify edge count
            edges = client.submit("g.E().count()").all().result()
            assert edges == [1]

            # Verify edge label
            labels = client.submit("g.E().label()").all().result()
            assert "knows" in labels
        finally:
            client.close()

    def test_gremlin_traversal_api(self, deployed_env):
        """Test Gremlin traversal bytecode API."""
        cluster_port = deployed_env.get("CLUSTER_PORT")
        assert cluster_port, "CLUSTER_PORT must be set for Gremlin tests"

        url = f"ws://localhost.localstack.cloud:{cluster_port}/gremlin"

        # Use string API to clear first (bytecode iterate() has version compat issues)
        client = GremlinClient(url, "g")
        try:
            client.submit("g.V().drop()").all().result()
        finally:
            client.close()

        # Use bytecode traversal API
        conn = DriverRemoteConnection(url, "g")
        try:
            g = traversal().with_remote(conn)

            g.addV("city").property("name", "Berlin").next()
            g.addV("city").property("name", "Paris").next()

            count = g.V().count().next()
            assert count == 2

            names = sorted(g.V().values("name").toList())
            assert names == ["Berlin", "Paris"]
        finally:
            conn.close()
