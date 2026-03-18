#!/usr/bin/env python3
"""CDK app for EMR Serverless Spark sample."""

import aws_cdk as cdk
from aws_cdk import (
    CfnOutput,
    Stack,
    aws_emrserverless as emrserverless,
    aws_iam as iam,
    aws_s3 as s3,
)
from constructs import Construct


class EmrServerlessSparkStack(Stack):
    def __init__(self, scope: Construct, id: str, **kwargs):
        super().__init__(scope, id, **kwargs)

        # S3 bucket for job artifacts and logs
        bucket = s3.Bucket(
            self, "EmrBucket",
            bucket_name="emr-spark-cdk",
            removal_policy=cdk.RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # IAM role for EMR Serverless
        role = iam.Role(
            self, "EmrRole",
            role_name="emr-serverless-role-cdk",
            assumed_by=iam.ServicePrincipal("emr-serverless.amazonaws.com"),
        )

        # EMR Serverless application
        app = emrserverless.CfnApplication(
            self, "SparkApp",
            name="serverless-java-demo-cdk",
            release_label="emr-6.9.0",
            type="SPARK",
        )

        CfnOutput(self, "AppName", value="serverless-java-demo-cdk")
        CfnOutput(self, "AppId", value=app.ref)
        CfnOutput(self, "S3Bucket", value=bucket.bucket_name)
        CfnOutput(self, "JobRoleArn", value=role.role_arn)


app = cdk.App()
EmrServerlessSparkStack(app, "EmrServerlessSparkStack")
app.synth()
