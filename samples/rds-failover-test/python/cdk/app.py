#!/usr/bin/env python3
"""
RDS Failover Test CDK application.

Note: CDK can only deploy to a single region at a time.
The secondary cluster must be created separately via CLI.
"""

import os

from aws_cdk import (
    App,
    CfnOutput,
    Stack,
    aws_rds as rds,
)
from constructs import Construct


class RdsFailoverTestStack(Stack):
    """Stack for RDS global cluster resources (primary region only)."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        global_cluster_id = os.environ.get("GLOBAL_CLUSTER_ID", "global-cluster")
        primary_cluster_id = os.environ.get("PRIMARY_CLUSTER_ID", "rds-cluster-1")

        # Global cluster
        global_cluster = rds.CfnGlobalCluster(
            self,
            "GlobalCluster",
            global_cluster_identifier=global_cluster_id,
            engine="aurora-postgresql",
            engine_version="13.7",
            database_name="test",
        )

        # Primary cluster
        primary_cluster = rds.CfnDBCluster(
            self,
            "PrimaryCluster",
            db_cluster_identifier=primary_cluster_id,
            engine="aurora-postgresql",
            engine_version="13.7",
            database_name="test",
            global_cluster_identifier=global_cluster_id,
            master_username="admin",
            master_user_password="adminpassword",
        )
        primary_cluster.add_dependency(global_cluster)

        # Primary instance
        primary_instance = rds.CfnDBInstance(
            self,
            "PrimaryInstance",
            db_cluster_identifier=primary_cluster_id,
            db_instance_identifier="inst-1",
            db_instance_class="db.r5.large",
            engine="aurora-postgresql",
            engine_version="13.7",
        )
        primary_instance.add_dependency(primary_cluster)

        # Outputs
        CfnOutput(self, "GlobalClusterId", value=global_cluster_id)
        CfnOutput(self, "PrimaryClusterId", value=primary_cluster_id)
        CfnOutput(self, "PrimaryArn", value=primary_cluster.attr_db_cluster_arn)


app = App()
RdsFailoverTestStack(app, "RdsFailoverTestStack")
app.synth()
