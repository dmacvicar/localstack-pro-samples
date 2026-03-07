#!/usr/bin/env python3
"""CDK app for CloudWatch Metrics with Lambda and SNS Alarm."""

import os
from pathlib import Path

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    aws_lambda as lambda_,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_iam as iam,
    CfnOutput,
)
from constructs import Construct


class CloudWatchMetricsStack(Stack):
    """Stack for CloudWatch Metrics with Lambda and SNS Alarm."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration
        function_name = os.environ.get("FUNCTION_NAME", "cw-failing-lambda")
        topic_name = os.environ.get("TOPIC_NAME", "cw-alarm-topic")
        alarm_name = os.environ.get("ALARM_NAME", "cw-lambda-alarm")
        test_email = os.environ.get("TEST_EMAIL", "test@example.com")

        # Lambda Role
        lambda_role = iam.Role(
            self,
            "LambdaRole",
            role_name="cw-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Lambda function
        handler_path = Path(__file__).parent.parent
        lambda_fn = lambda_.Function(
            self,
            "FailingLambda",
            function_name=function_name,
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="handler.lambda_handler",
            code=lambda_.Code.from_asset(str(handler_path), exclude=["cdk", "terraform", "cloudformation", "scripts", "__pycache__", "*.pyc"]),
            role=lambda_role,
            timeout=Duration.seconds(30),
        )

        # SNS Topic
        topic = sns.Topic(
            self,
            "AlarmTopic",
            topic_name=topic_name,
        )

        # Email subscription
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(test_email)
        )

        # CloudWatch Alarm
        alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=alarm_name,
            metric=lambda_fn.metric_errors(
                period=Duration.minutes(1),
                statistic="Sum",
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        alarm.add_alarm_action(cw_actions.SnsAction(topic))

        # Outputs
        CfnOutput(self, "FunctionName", value=lambda_fn.function_name)
        CfnOutput(self, "LambdaArn", value=lambda_fn.function_arn)
        CfnOutput(self, "TopicName", value=topic.topic_name)
        CfnOutput(self, "TopicArn", value=topic.topic_arn)
        CfnOutput(self, "AlarmName", value=alarm.alarm_name)
        CfnOutput(self, "TestEmail", value=test_email)


app = cdk.App()
CloudWatchMetricsStack(
    app,
    "CloudWatchMetricsStack",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT", "000000000000"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    ),
)
app.synth()
