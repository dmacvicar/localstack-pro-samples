#!/usr/bin/env python3
"""CDK app for Reproducible ML sample."""

import aws_cdk as cdk
from aws_cdk import (
    CfnOutput,
    Duration,
    Stack,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_s3 as s3,
)
from constructs import Construct


class ReproducibleMlStack(Stack):
    def __init__(self, scope: Construct, id: str, **kwargs):
        super().__init__(scope, id, **kwargs)

        bucket = s3.Bucket(
            self, "MlBucket",
            bucket_name="reproducible-ml-cdk",
            removal_policy=cdk.RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        role = iam.Role(
            self, "LambdaRole",
            role_name="ml-lambda-role-cdk",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
        )

        sklearn_layer = lambda_.LayerVersion.from_layer_version_arn(
            self, "SklearnLayer",
            "arn:aws:lambda:us-east-1:446751924810:layer:python-3-8-scikit-learn-0-22-0:3",
        )

        train_fn = lambda_.Function(
            self, "TrainFunction",
            function_name="ml-train-cdk",
            runtime=lambda_.Runtime.PYTHON_3_8,
            handler="train.handler",
            role=role,
            timeout=Duration.seconds(600),
            code=lambda_.Code.from_bucket(bucket, "ml-train.zip"),
            layers=[sklearn_layer],
            environment={"S3_BUCKET": "reproducible-ml-cdk"},
        )

        predict_fn = lambda_.Function(
            self, "PredictFunction",
            function_name="ml-predict-cdk",
            runtime=lambda_.Runtime.PYTHON_3_8,
            handler="infer.handler",
            role=role,
            timeout=Duration.seconds(600),
            code=lambda_.Code.from_bucket(bucket, "ml-infer.zip"),
            layers=[sklearn_layer],
            environment={"S3_BUCKET": "reproducible-ml-cdk"},
        )

        CfnOutput(self, "S3Bucket", value=bucket.bucket_name)
        CfnOutput(self, "TrainFunctionOutput", value=train_fn.function_name)
        CfnOutput(self, "PredictFunctionOutput", value=predict_fn.function_name)


app = cdk.App()
ReproducibleMlStack(app, "ReproducibleMlStack")
app.synth()
