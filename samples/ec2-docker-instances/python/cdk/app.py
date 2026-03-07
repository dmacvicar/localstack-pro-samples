#!/usr/bin/env python3
"""CDK app for EC2 Docker Instances (requires EC2_VM_MANAGER=docker)."""

import os

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    CfnOutput,
)
from constructs import Construct


class Ec2DockerInstancesStack(Stack):
    """Stack for EC2 Docker Instances."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration
        ami_id = os.environ.get("AMI_ID", "ami-00a001")
        instance_name = os.environ.get("INSTANCE_NAME", "ec2-docker-test")

        # VPC (use default)
        vpc = ec2.Vpc.from_lookup(
            self,
            "DefaultVpc",
            is_default=True,
        )

        # EC2 Instance using the Docker-backed AMI
        instance = ec2.Instance(
            self,
            "DockerInstance",
            instance_name=instance_name,
            vpc=vpc,
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T2,
                ec2.InstanceSize.MICRO,
            ),
            machine_image=ec2.GenericLinuxImage({
                os.environ.get("CDK_DEFAULT_REGION", "us-east-1"): ami_id,
            }),
        )

        # Outputs
        CfnOutput(self, "AmiId", value=ami_id)
        CfnOutput(self, "InstanceId", value=instance.instance_id)
        CfnOutput(self, "InstanceName", value=instance_name)
        CfnOutput(self, "PrivateIp", value=instance.instance_private_ip)
        CfnOutput(self, "PublicIp", value=instance.instance_public_ip)


app = cdk.App()
Ec2DockerInstancesStack(
    app,
    "Ec2DockerInstancesStack",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT", "000000000000"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    ),
)
app.synth()
