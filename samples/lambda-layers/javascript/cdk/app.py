#!/usr/bin/env python3
"""CDK app for Lambda Layers sample."""

import os
from pathlib import Path

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_lambda as lambda_,
    CfnOutput,
    RemovalPolicy,
    Duration,
)
from constructs import Construct


class LambdaLayersStack(Stack):
    """Stack for Lambda function with shared layer."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        function_name = "lambda-layers-cdk"
        layer_name = "shared-layer-cdk"

        # Get the project directory (parent of cdk/)
        project_dir = Path(__file__).parent.parent

        # Lambda Layer
        layer = lambda_.LayerVersion(
            self,
            "SharedLayer",
            layer_version_name=layer_name,
            description="Shared utility library",
            code=lambda_.Code.from_asset(str(project_dir / "layer")),
            compatible_runtimes=[
                lambda_.Runtime.NODEJS_18_X,
                lambda_.Runtime.NODEJS_20_X,
            ],
            removal_policy=RemovalPolicy.DESTROY,
        )

        CfnOutput(self, "LayerArn", value=layer.layer_version_arn)
        CfnOutput(self, "LayerName", value=layer_name)

        # Lambda Function
        fn = lambda_.Function(
            self,
            "HelloFunction",
            function_name=function_name,
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="handler.hello",
            code=lambda_.Code.from_asset(
                str(project_dir),
                exclude=["node_modules", "scripts", "layer", ".serverless", "*.pyc", "__pycache__", "terraform", "cloudformation", "cdk"],
            ),
            timeout=Duration.seconds(30),
            memory_size=128,
            layers=[layer],
        )

        CfnOutput(self, "FunctionName", value=fn.function_name)
        CfnOutput(self, "FunctionArn", value=fn.function_arn)


app = cdk.App()
LambdaLayersStack(
    app,
    "LambdaLayersStack",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT", "000000000000"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    ),
)
app.synth()
