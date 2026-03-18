#!/usr/bin/env python3
"""CDK app for SageMaker Inference sample."""

import aws_cdk as cdk
from aws_cdk import (
    CfnOutput,
    Stack,
    aws_iam as iam,
    aws_s3 as s3,
    aws_sagemaker as sagemaker,
)
from constructs import Construct


class SagemakerInferenceStack(Stack):
    def __init__(self, scope: Construct, id: str, **kwargs):
        super().__init__(scope, id, **kwargs)

        bucket = s3.Bucket(
            self, "ModelBucket",
            bucket_name="sagemaker-models-cdk",
            removal_policy=cdk.RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        role = iam.Role(
            self, "SageMakerRole",
            role_name="sagemaker-role-cdk",
            assumed_by=iam.ServicePrincipal("sagemaker.amazonaws.com"),
        )

        model = sagemaker.CfnModel(
            self, "Model",
            model_name="sample-cdk",
            execution_role_arn=role.role_arn,
            primary_container=sagemaker.CfnModel.ContainerDefinitionProperty(
                image="763104351884.dkr.ecr.us-east-1.amazonaws.com/pytorch-inference:1.5.0-cpu-py3",
                model_data_url=f"s3://{bucket.bucket_name}/model.tar.gz",
            ),
        )

        config = sagemaker.CfnEndpointConfig(
            self, "EndpointConfig",
            endpoint_config_name="sample-cf-cdk",
            production_variants=[
                sagemaker.CfnEndpointConfig.ProductionVariantProperty(
                    variant_name="var-1",
                    model_name="sample-cdk",
                    initial_instance_count=1,
                    instance_type="ml.m5.large",
                ),
            ],
        )
        config.add_dependency(model)

        endpoint = sagemaker.CfnEndpoint(
            self, "Endpoint",
            endpoint_name="sample-ep-cdk",
            endpoint_config_name="sample-cf-cdk",
        )
        endpoint.add_dependency(config)

        CfnOutput(self, "S3Bucket", value=bucket.bucket_name)
        CfnOutput(self, "ModelName", value="sample-cdk")
        CfnOutput(self, "ConfigName", value="sample-cf-cdk")
        CfnOutput(self, "EndpointNameOutput", value="sample-ep-cdk")


app = cdk.App()
SagemakerInferenceStack(app, "SagemakerInferenceStack")
app.synth()
