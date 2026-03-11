"""
Tests for RDS Database Queries sample.

Run all IaC methods:
    uv run pytest samples/rds-db-queries/python/ -v

Run specific IaC method:
    uv run pytest samples/rds-db-queries/python/ -v -k scripts

Note: First run requires PostgreSQL Docker image download.
"""

import sys
from pathlib import Path

import psycopg2
import pytest

# Add samples directory to path for conftest imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from conftest import (
    AWSClients,
    WaitFor,
    run_deploy,
    get_sample_dir,
)

SAMPLE_NAME = "rds-db-queries"
LANGUAGE = "python"

# IaC methods to test
IAC_METHODS = ["scripts", "terraform", "cloudformation", "cdk"]


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

    # Longer timeout for first run (PostgreSQL image download)
    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method, timeout=600)

    # Add IaC method to env for test identification
    env["_IAC_METHOD"] = iac_method

    return env


class TestRdsDbQueries:
    """Test RDS database instance and queries."""

    def test_instance_exists(self, deployed_env, aws_clients: AWSClients):
        """Test that the RDS instance was created."""
        db_instance_id = deployed_env.get("DB_INSTANCE_ID")
        assert db_instance_id, "DB_INSTANCE_ID should be set"

        response = aws_clients.rds_client.describe_db_instances(
            DBInstanceIdentifier=db_instance_id
        )
        assert len(response["DBInstances"]) == 1
        assert response["DBInstances"][0]["DBInstanceIdentifier"] == db_instance_id

    def test_instance_is_postgres(self, deployed_env, aws_clients: AWSClients):
        """Test that the instance is PostgreSQL."""
        db_instance_id = deployed_env.get("DB_INSTANCE_ID")

        response = aws_clients.rds_client.describe_db_instances(
            DBInstanceIdentifier=db_instance_id
        )
        engine = response["DBInstances"][0]["Engine"]
        assert engine == "postgres"

    def test_instance_is_available(self, deployed_env, aws_clients: AWSClients):
        """Test that the instance is available."""
        db_instance_id = deployed_env.get("DB_INSTANCE_ID")

        response = aws_clients.rds_client.describe_db_instances(
            DBInstanceIdentifier=db_instance_id
        )
        status = response["DBInstances"][0]["DBInstanceStatus"]
        assert status == "available"

    def test_can_connect(self, deployed_env):
        """Test that we can connect to the database."""
        db_host = deployed_env.get("DB_HOST")
        db_port = deployed_env.get("DB_PORT")
        db_name = deployed_env.get("DB_NAME")
        db_user = deployed_env.get("DB_USER")
        db_password = deployed_env.get("DB_PASSWORD")

        conn = psycopg2.connect(
            host=db_host,
            port=int(db_port),
            dbname=db_name,
            user=db_user,
            password=db_password,
        )
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                result = cur.fetchone()
                assert result[0] == 1
        finally:
            conn.close()

    def test_create_and_query_table(self, deployed_env):
        """Test creating a table and running queries."""
        db_host = deployed_env.get("DB_HOST")
        db_port = deployed_env.get("DB_PORT")
        db_name = deployed_env.get("DB_NAME")
        db_user = deployed_env.get("DB_USER")
        db_password = deployed_env.get("DB_PASSWORD")

        conn = psycopg2.connect(
            host=db_host,
            port=int(db_port),
            dbname=db_name,
            user=db_user,
            password=db_password,
        )
        try:
            with conn.cursor() as cur:
                # Create table
                cur.execute("""
                    CREATE TABLE IF NOT EXISTS test_person (
                        id SERIAL PRIMARY KEY,
                        name VARCHAR(100) NOT NULL
                    )
                """)
                conn.commit()

                # Insert data
                cur.execute("INSERT INTO test_person (name) VALUES ('Alice')")
                cur.execute("INSERT INTO test_person (name) VALUES ('Bob')")
                cur.execute("INSERT INTO test_person (name) VALUES ('Charlie')")
                conn.commit()

                # Query data
                cur.execute("SELECT name FROM test_person ORDER BY id")
                results = cur.fetchall()

                assert len(results) == 3
                assert results[0][0] == "Alice"
                assert results[1][0] == "Bob"
                assert results[2][0] == "Charlie"

                # Cleanup
                cur.execute("DROP TABLE test_person")
                conn.commit()
        finally:
            conn.close()

    def test_database_exists(self, deployed_env):
        """Test that the configured database exists."""
        db_host = deployed_env.get("DB_HOST")
        db_port = deployed_env.get("DB_PORT")
        db_name = deployed_env.get("DB_NAME")
        db_user = deployed_env.get("DB_USER")
        db_password = deployed_env.get("DB_PASSWORD")

        conn = psycopg2.connect(
            host=db_host,
            port=int(db_port),
            dbname=db_name,
            user=db_user,
            password=db_password,
        )
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT datname FROM pg_database WHERE datname = %s",
                    (db_name,)
                )
                result = cur.fetchone()
                assert result is not None
                assert result[0] == db_name
        finally:
            conn.close()
