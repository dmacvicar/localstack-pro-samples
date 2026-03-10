#!/usr/bin/env python3
"""
Glue ETL Jobs CDK application.
Aurora PostgreSQL + Glue catalog (database, tables, JDBC connection, job) + S3.
"""

import os

from aws_cdk import (
    App,
    CfnOutput,
    Stack,
    aws_s3 as s3,
    aws_rds as rds,
    aws_glue as glue,
    aws_secretsmanager as secretsmanager,
    RemovalPolicy,
)
from constructs import Construct


class GlueEtlJobsStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        cluster_id = "glue-etl-cluster1"
        connection_name = "glue-etl-cluster1-connection"
        job_name = "test-job1"
        script_bucket_name = "glue-pyspark-test"
        target_bucket_name = "glue-sample-target"

        # S3 buckets
        script_bucket = s3.Bucket(
            self,
            "ScriptsBucket",
            bucket_name=script_bucket_name,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        target_bucket = s3.Bucket(
            self,
            "TargetBucket",
            bucket_name=target_bucket_name,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Aurora PostgreSQL cluster
        cluster = rds.CfnDBCluster(
            self,
            "AuroraCluster",
            db_cluster_identifier=cluster_id,
            engine="aurora-postgresql",
            database_name="test",
            master_username="test",
            master_user_password="test",
        )

        # Secrets Manager secret
        secret = secretsmanager.CfnSecret(
            self,
            "RdsSecret",
            name="pass",
            secret_string="test",
        )

        # Glue database
        database = glue.CfnDatabase(
            self,
            "GlueDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name="legislators",
            ),
        )

        # Glue tables
        memberships_table = glue.CfnTable(
            self,
            "MembershipsTable",
            catalog_id=self.account,
            database_name="legislators",
            table_input=glue.CfnTable.TableInputProperty(
                name="memberships_json",
                parameters={"connectionName": connection_name},
                storage_descriptor=glue.CfnTable.StorageDescriptorProperty(
                    location="test.memberships",
                ),
            ),
        )
        memberships_table.add_dependency(database)

        persons_table = glue.CfnTable(
            self,
            "PersonsTable",
            catalog_id=self.account,
            database_name="legislators",
            table_input=glue.CfnTable.TableInputProperty(
                name="persons_json",
                parameters={"connectionName": connection_name},
                storage_descriptor=glue.CfnTable.StorageDescriptorProperty(
                    location="test.persons",
                ),
            ),
        )
        persons_table.add_dependency(database)

        organizations_table = glue.CfnTable(
            self,
            "OrganizationsTable",
            catalog_id=self.account,
            database_name="legislators",
            table_input=glue.CfnTable.TableInputProperty(
                name="organizations_json",
                parameters={"connectionName": connection_name},
                storage_descriptor=glue.CfnTable.StorageDescriptorProperty(
                    location="test.organizations",
                ),
            ),
        )
        organizations_table.add_dependency(database)

        # Glue JDBC connection
        connection = glue.CfnConnection(
            self,
            "GlueConnection",
            catalog_id=self.account,
            connection_input=glue.CfnConnection.ConnectionInputProperty(
                name=connection_name,
                connection_type="JDBC",
                connection_properties={
                    "USERNAME": "test",
                    "PASSWORD": "test",
                    "JDBC_CONNECTION_URL": f"jdbc:postgresql://localhost.localstack.cloud:{cluster.attr_endpoint_port}",
                },
            ),
        )
        connection.add_dependency(cluster)

        # Glue job
        job = glue.CfnJob(
            self,
            "GlueJob",
            name=job_name,
            role="r1",
            command=glue.CfnJob.JobCommandProperty(
                name="pythonshell",
                script_location=f"s3://{script_bucket_name}/job.py",
            ),
            connections=glue.CfnJob.ConnectionsListProperty(
                connections=[cluster_id],
            ),
        )
        job.add_dependency(connection)
        job.add_dependency(memberships_table)
        job.add_dependency(persons_table)
        job.add_dependency(organizations_table)

        # Outputs
        CfnOutput(self, "ClusterIdentifier", value=cluster_id)
        CfnOutput(self, "ClusterPort", value=cluster.attr_endpoint_port)
        CfnOutput(self, "ConnectionName", value=connection_name)
        CfnOutput(self, "JobName", value=job_name)
        CfnOutput(self, "ScriptBucketName", value=script_bucket_name)
        CfnOutput(self, "TargetBucketName", value=target_bucket_name)
        CfnOutput(self, "SecretArn", value=secret.ref)


app = App()
GlueEtlJobsStack(
    app,
    "GlueEtlJobsStack",
    env={
        "account": os.environ.get("CDK_DEFAULT_ACCOUNT", "000000000000"),
        "region": os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    },
)
app.synth()
