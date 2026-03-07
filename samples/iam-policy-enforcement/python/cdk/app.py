#!/usr/bin/env python3
"""CDK app for IAM Policy Enforcement."""

import os

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_iam as iam,
    CfnOutput,
)
from constructs import Construct


class IamPolicyEnforcementStack(Stack):
    """Stack for IAM Policy Enforcement."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration
        user_name = os.environ.get("USER_NAME", "iam-test-user")
        policy_name = os.environ.get("POLICY_NAME", "iam-test-policy")

        # IAM Policy
        policy = iam.ManagedPolicy(
            self,
            "TestPolicy",
            managed_policy_name=policy_name,
            statements=[
                iam.PolicyStatement(
                    sid="AllowKinesisAndS3",
                    effect=iam.Effect.ALLOW,
                    actions=["kinesis:*", "s3:*"],
                    resources=["*"],
                )
            ],
        )

        # IAM User
        user = iam.User(
            self,
            "TestUser",
            user_name=user_name,
            managed_policies=[policy],
        )

        # IAM Access Key
        access_key = iam.CfnAccessKey(
            self,
            "TestAccessKey",
            user_name=user.user_name,
        )

        # Outputs
        CfnOutput(self, "UserName", value=user.user_name)
        CfnOutput(self, "PolicyName", value=policy.managed_policy_name)
        CfnOutput(self, "PolicyArn", value=policy.managed_policy_arn)
        CfnOutput(self, "AccessKeyId", value=access_key.ref)
        CfnOutput(self, "SecretAccessKey", value=access_key.attr_secret_access_key)


app = cdk.App()
IamPolicyEnforcementStack(
    app,
    "IamPolicyEnforcementStack",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT", "000000000000"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    ),
)
app.synth()
