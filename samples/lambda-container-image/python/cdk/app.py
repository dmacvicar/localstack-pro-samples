#!/usr/bin/env python3
"""CDK app for Lambda Container Image sample."""

import os

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_ecr as ecr,
    aws_lambda as lambda_,
    CfnOutput,
    RemovalPolicy,
)
from constructs import Construct


class LambdaContainerImageStack(Stack):
    """Stack for Lambda function from container image."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        repo_name = "lambda-container-cdk"
        function_name = "lambda-container-cdk"

        # Get image URI from context (set by deploy script after pushing)
        image_uri = self.node.try_get_context("image_uri")

        # ECR Repository
        repo = ecr.Repository(
            self,
            "LambdaRepo",
            repository_name=repo_name,
            removal_policy=RemovalPolicy.DESTROY,
            empty_on_delete=True,
        )

        CfnOutput(self, "RepoName", value=repo.repository_name)
        CfnOutput(self, "RepoUri", value=repo.repository_uri)

        # Lambda function - only create if image_uri is provided
        if image_uri:
            fn = lambda_.Function(
                self,
                "ContainerLambda",
                function_name=function_name,
                runtime=lambda_.Runtime.FROM_IMAGE,
                handler=lambda_.Handler.FROM_IMAGE,
                code=lambda_.EcrImageCode.from_ecr_image(
                    repository=repo,
                    tag_or_digest="latest",
                ),
                timeout=cdk.Duration.seconds(30),
                memory_size=256,
            )

            CfnOutput(self, "FunctionName", value=fn.function_name)


app = cdk.App()
LambdaContainerImageStack(
    app,
    "LambdaContainerImageStack",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT", "000000000000"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    ),
)
app.synth()
