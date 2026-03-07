#!/usr/bin/env python3
"""
Glacier S3 Select CDK application.
"""

from pathlib import Path

from aws_cdk import (
    App,
    CfnOutput,
    RemovalPolicy,
    Stack,
    aws_glacier as glacier,
    aws_s3 as s3,
    aws_s3_deployment as s3deploy,
)
from constructs import Construct


class GlacierS3SelectStack(Stack):
    """Stack for Glacier S3 Select resources."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        bucket_name = "glacier-s3-select"
        results_bucket_name = "glacier-results"
        vault_name = "glacier-vault"

        # Get path to data file
        sample_dir = Path(__file__).parent.parent

        # S3 bucket for CSV data
        data_bucket = s3.Bucket(
            self,
            "DataBucket",
            bucket_name=bucket_name,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # S3 bucket for query results
        results_bucket = s3.Bucket(
            self,
            "ResultsBucket",
            bucket_name=results_bucket_name,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Upload CSV data file
        s3deploy.BucketDeployment(
            self,
            "DeployData",
            sources=[s3deploy.Source.asset(str(sample_dir), exclude=["**/*", "!data.csv"])],
            destination_bucket=data_bucket,
        )

        # Glacier vault
        vault = glacier.CfnVault(
            self,
            "GlacierVault",
            vault_name=vault_name,
        )

        # Outputs
        CfnOutput(self, "BucketName", value=data_bucket.bucket_name)
        CfnOutput(self, "ResultsBucket", value=results_bucket.bucket_name)
        CfnOutput(self, "VaultName", value=vault_name)


app = App()
GlacierS3SelectStack(app, "GlacierS3SelectStack")
app.synth()
