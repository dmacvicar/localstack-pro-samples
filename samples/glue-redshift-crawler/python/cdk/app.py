#!/usr/bin/env python3
"""
Glue Redshift Crawler CDK application.
"""

from aws_cdk import (
    App,
    CfnOutput,
    Stack,
    aws_glue as glue,
    aws_iam as iam,
    aws_redshift as redshift,
)
from constructs import Construct


class GlueRedshiftCrawlerStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        cluster_id = "redshift-cdk"
        db_name = "db1"
        username = "testuser"
        password = "testPass123"
        glue_db_name = "gluedb-cdk"

        # IAM role for Glue
        glue_role = iam.Role(
            self,
            "GlueRole",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
        )

        # Redshift cluster
        cluster = redshift.CfnCluster(
            self,
            "RedshiftCluster",
            cluster_identifier=cluster_id,
            db_name=db_name,
            master_username=username,
            master_user_password=password,
            node_type="dc2.large",
            cluster_type="single-node",
        )

        # Glue database
        glue_db = glue.CfnDatabase(
            self,
            "GlueDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=glue_db_name,
            ),
        )

        # Glue connection
        conn_name = "glueconn-cdk"
        glue_conn = glue.CfnConnection(
            self,
            "GlueConnection",
            catalog_id=self.account,
            connection_input=glue.CfnConnection.ConnectionInputProperty(
                name=conn_name,
                connection_type="JDBC",
                connection_properties={
                    "USERNAME": username,
                    "PASSWORD": password,
                    "JDBC_CONNECTION_URL": f"jdbc:redshift://{cluster.attr_endpoint_address}:{cluster.attr_endpoint_port}/{db_name}",
                },
            ),
        )

        # Glue crawler
        crawler_name = "crawler-cdk"
        crawler = glue.CfnCrawler(
            self,
            "GlueCrawler",
            name=crawler_name,
            database_name=glue_db_name,
            role=glue_role.role_arn,
            targets=glue.CfnCrawler.TargetsProperty(
                jdbc_targets=[
                    glue.CfnCrawler.JdbcTargetProperty(
                        connection_name=conn_name,
                        path=f"{db_name}/%/sales",
                    )
                ],
            ),
        )
        crawler.add_dependency(glue_db)
        crawler.add_dependency(glue_conn)

        # Outputs
        CfnOutput(self, "RedshiftClusterId", value=cluster_id)
        CfnOutput(self, "RedshiftDBName", value=db_name)
        CfnOutput(self, "RedshiftTableName", value="sales")
        CfnOutput(self, "RedshiftSchemaName", value="public")
        CfnOutput(self, "RedshiftUsername", value=username)
        CfnOutput(self, "RedshiftHost", value=cluster.attr_endpoint_address)
        CfnOutput(self, "RedshiftPort", value=cluster.attr_endpoint_port)
        CfnOutput(self, "GlueDBName", value=glue_db_name)
        CfnOutput(self, "GlueConnectionName", value=conn_name)
        CfnOutput(self, "GlueCrawlerName", value=crawler_name)
        CfnOutput(self, "GlueTableName", value=f"{db_name}_public_sales")


app = App()
GlueRedshiftCrawlerStack(app, "GlueRedshiftCrawlerStack")
app.synth()
