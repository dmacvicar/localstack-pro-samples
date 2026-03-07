#!/usr/bin/env python3
"""
Transfer FTP to S3 CDK application.
"""

from aws_cdk import (
    App,
    CfnOutput,
    RemovalPolicy,
    Stack,
    aws_iam as iam,
    aws_s3 as s3,
    aws_transfer as transfer,
)
from constructs import Construct


class TransferFtpS3Stack(Stack):
    """Stack for Transfer FTP server resources."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        bucket_name = "transfer-files"
        username = "ftpuser"

        # S3 bucket for file storage
        bucket = s3.Bucket(
            self,
            "TransferBucket",
            bucket_name=bucket_name,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # IAM role for Transfer service
        transfer_role = iam.Role(
            self,
            "TransferRole",
            role_name="transfer-role",
            assumed_by=iam.ServicePrincipal("transfer.amazonaws.com"),
        )

        # Grant the role access to the bucket
        bucket.grant_read_write(transfer_role)

        # Transfer server with FTP protocol
        server = transfer.CfnServer(
            self,
            "TransferServer",
            endpoint_type="PUBLIC",
            identity_provider_type="SERVICE_MANAGED",
            protocols=["FTP"],
        )

        # Transfer user
        user = transfer.CfnUser(
            self,
            "TransferUser",
            server_id=server.attr_server_id,
            user_name=username,
            role=transfer_role.role_arn,
            home_directory_type="PATH",
            home_directory=f"/{bucket_name}",
        )

        # Outputs
        CfnOutput(self, "ServerId", value=server.attr_server_id)
        CfnOutput(self, "BucketName", value=bucket.bucket_name)
        CfnOutput(self, "Username", value=username)


app = App()
TransferFtpS3Stack(app, "TransferFtpS3Stack")
app.synth()
