"""
Tests for Glue ETL Jobs sample (Python).

Run with:
    uv run pytest samples/glue-etl-jobs/python/ -v

Note: This sample requires Docker for the Aurora PostgreSQL cluster
and the Glue Spark executor. First run may take several minutes for
Spark context initialization.
"""

from pathlib import Path

import pytest

# Sample configuration
SAMPLE_NAME = "glue-etl-jobs"
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

    # Long timeout: Aurora cluster + Glue Spark job can take several minutes
    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method, timeout=900)

    return env


class TestGlueEtlJobs:
    """Test suite for Glue ETL Jobs sample."""

    def test_glue_database_exists(self, deployed_env, aws_clients):
        """Glue database should exist."""
        response = aws_clients.glue_client.get_database(Name="legislators")
        assert response["Database"]["Name"] == "legislators"

    def test_glue_tables_exist(self, deployed_env, aws_clients):
        """All three Glue catalog tables should exist."""
        expected_tables = ["persons_json", "memberships_json", "organizations_json"]
        for table_name in expected_tables:
            response = aws_clients.glue_client.get_table(
                DatabaseName="legislators", Name=table_name
            )
            assert response["Table"]["Name"] == table_name

    def test_glue_connection_exists(self, deployed_env, aws_clients):
        """Glue JDBC connection should exist."""
        connection_name = deployed_env["CONNECTION_NAME"]
        response = aws_clients.glue_client.get_connection(Name=connection_name)
        conn = response["Connection"]
        assert conn["Name"] == connection_name
        assert conn["ConnectionType"] == "JDBC"

    def test_glue_job_exists(self, deployed_env, aws_clients):
        """Glue job should exist."""
        job_name = deployed_env["JOB_NAME"]
        response = aws_clients.glue_client.get_job(JobName=job_name)
        assert response["Job"]["Name"] == job_name

    def test_glue_job_run_succeeded(self, deployed_env, aws_clients):
        """Glue job run should have succeeded."""
        job_name = deployed_env["JOB_NAME"]
        run_id = deployed_env["JOB_RUN_ID"]

        response = aws_clients.glue_client.get_job_run(
            JobName=job_name, RunId=run_id
        )
        assert response["JobRun"]["JobRunState"] == "SUCCEEDED"

    def test_s3_script_uploaded(self, deployed_env, aws_clients):
        """Job script should be in S3."""
        bucket = deployed_env["BUCKET"]
        response = aws_clients.s3_client.list_objects_v2(
            Bucket=bucket, Prefix="job.py"
        )
        objects = response.get("Contents", [])
        assert len(objects) == 1, "job.py should exist in script bucket"

    def test_s3_output_exists(self, deployed_env, aws_clients):
        """Glue job should have written output to S3."""
        bucket = deployed_env["TARGET_BUCKET"]
        response = aws_clients.s3_client.list_objects_v2(
            Bucket=bucket, Prefix="output-dir/"
        )
        objects = response.get("Contents", [])
        assert len(objects) > 0, "Output files should exist in target bucket"

    def test_s3_parquet_history_output(self, deployed_env, aws_clients):
        """Glue job should have written parquet files to legislator_history."""
        bucket = deployed_env["TARGET_BUCKET"]
        response = aws_clients.s3_client.list_objects_v2(
            Bucket=bucket, Prefix="output-dir/legislator_history/"
        )
        objects = response.get("Contents", [])
        assert len(objects) > 0, "Parquet files should exist in legislator_history"

    def test_s3_partitioned_output(self, deployed_env, aws_clients):
        """Glue job should have written partitioned parquet files."""
        bucket = deployed_env["TARGET_BUCKET"]
        response = aws_clients.s3_client.list_objects_v2(
            Bucket=bucket, Prefix="output-dir/legislator_part/"
        )
        objects = response.get("Contents", [])
        assert len(objects) > 0, "Partitioned parquet files should exist"

    def test_rds_cluster_exists(self, deployed_env, aws_clients):
        """RDS Aurora cluster should exist."""
        cluster_id = deployed_env["CLUSTER_IDENTIFIER"]
        response = aws_clients.rds_client.describe_db_clusters(
            DBClusterIdentifier=cluster_id
        )
        assert len(response["DBClusters"]) == 1
        assert response["DBClusters"][0]["DBClusterIdentifier"] == cluster_id
