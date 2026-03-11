#!/usr/bin/env python3
"""
RDS Database Queries CDK application.
"""

import os

from aws_cdk import (
    App,
    CfnOutput,
    Stack,
    aws_rds as rds,
)
from constructs import Construct


class RdsDbQueriesStack(Stack):
    """Stack for RDS PostgreSQL instance."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        db_instance_id = os.environ.get("DB_INSTANCE_ID", "rds-db")
        db_name = os.environ.get("DB_NAME", "testdb")
        db_user = os.environ.get("DB_USER", "testuser")
        db_password = os.environ.get("DB_PASSWORD", "testpass123")

        # RDS PostgreSQL instance
        db_instance = rds.CfnDBInstance(
            self,
            "DBInstance",
            db_instance_identifier=db_instance_id,
            db_instance_class="db.t3.micro",
            engine="postgres",
            db_name=db_name,
            master_username=db_user,
            master_user_password=db_password,
        )

        # Outputs
        CfnOutput(self, "DBInstanceId", value=db_instance_id)
        CfnOutput(self, "DBName", value=db_name)
        CfnOutput(self, "DBUser", value=db_user)


app = App()
RdsDbQueriesStack(app, "RdsDbQueriesStack")
app.synth()
