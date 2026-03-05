#!/usr/bin/env python3
"""CDK app for ECS ECR Container App sample."""

import os

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_ecr as ecr,
    aws_ecs as ecs,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_logs as logs,
    CfnOutput,
    RemovalPolicy,
)
from constructs import Construct


class EcsEcrAppStack(Stack):
    """Stack for ECS with ECR container image."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        repo_name = "ecs-ecr-cdk"
        cluster_name = "ecs-ecr-cdk-cluster"

        # Get image URI from context (set by deploy script after pushing)
        image_uri = self.node.try_get_context("image_uri")

        # ECR Repository
        repo = ecr.Repository(
            self,
            "AppRepo",
            repository_name=repo_name,
            removal_policy=RemovalPolicy.DESTROY,
            empty_on_delete=True,
        )

        CfnOutput(self, "RepoName", value=repo.repository_name)
        CfnOutput(self, "RepoUri", value=repo.repository_uri)

        # VPC
        vpc = ec2.Vpc(
            self,
            "Vpc",
            vpc_name="ecs-ecr-cdk-vpc",
            max_azs=1,
            nat_gateways=0,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                )
            ],
        )

        # Security Group
        security_group = ec2.SecurityGroup(
            self,
            "ContainerSG",
            vpc=vpc,
            description="Security group for ECS containers",
            allow_all_outbound=True,
        )
        security_group.add_ingress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.tcp(80),
            "Allow HTTP",
        )
        security_group.add_ingress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.tcp(8080),
            "Allow 8080",
        )

        # ECS Cluster
        cluster = ecs.Cluster(
            self,
            "Cluster",
            cluster_name=cluster_name,
            vpc=vpc,
        )

        CfnOutput(self, "ClusterName", value=cluster.cluster_name)

        # Only create task/service if image_uri is provided
        if image_uri:
            # Log Group
            log_group = logs.LogGroup(
                self,
                "LogGroup",
                log_group_name="/ecs/ecs-ecr-cdk",
                retention=logs.RetentionDays.ONE_DAY,
                removal_policy=RemovalPolicy.DESTROY,
            )

            # Task Definition
            task_definition = ecs.FargateTaskDefinition(
                self,
                "TaskDef",
                family="ecs-ecr-cdk-task",
                cpu=256,
                memory_limit_mib=512,
            )

            task_definition.add_container(
                "nginx",
                image=ecs.ContainerImage.from_registry(image_uri),
                essential=True,
                port_mappings=[
                    ecs.PortMapping(container_port=80, protocol=ecs.Protocol.TCP)
                ],
                logging=ecs.LogDrivers.aws_logs(
                    stream_prefix="ecs",
                    log_group=log_group,
                ),
            )

            # ECS Service
            service = ecs.FargateService(
                self,
                "Service",
                service_name="ecs-ecr-cdk-service",
                cluster=cluster,
                task_definition=task_definition,
                desired_count=1,
                assign_public_ip=True,
                security_groups=[security_group],
                vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            )

            CfnOutput(self, "ServiceName", value=service.service_name)


app = cdk.App()
EcsEcrAppStack(
    app,
    "EcsEcrAppStack",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT", "000000000000"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    ),
)
app.synth()
