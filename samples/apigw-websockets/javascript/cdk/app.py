#!/usr/bin/env python3
"""CDK app for API Gateway WebSockets sample."""

import os
from pathlib import Path

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_lambda as lambda_,
    aws_apigatewayv2 as apigwv2,
    aws_apigatewayv2_integrations as apigwv2_integrations,
    CfnOutput,
    Duration,
)
from constructs import Construct


class ApiGwWebsocketsStack(Stack):
    """Stack for API Gateway WebSocket API with Lambda handlers."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        api_name = "apigw-websockets-cdk"

        # Get the project directory (parent of cdk/)
        project_dir = Path(__file__).parent.parent

        # Lambda Functions
        connection_handler = lambda_.Function(
            self,
            "ConnectionHandler",
            function_name=f"{api_name}-connectionHandler",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="handler.handler",
            code=lambda_.Code.from_asset(
                str(project_dir),
                exclude=[
                    "node_modules",
                    "scripts",
                    ".serverless",
                    "*.pyc",
                    "__pycache__",
                    "terraform",
                    "cloudformation",
                    "cdk",
                ],
            ),
            timeout=Duration.seconds(30),
            memory_size=128,
        )

        default_handler = lambda_.Function(
            self,
            "DefaultHandler",
            function_name=f"{api_name}-defaultHandler",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="handler.handler",
            code=lambda_.Code.from_asset(
                str(project_dir),
                exclude=[
                    "node_modules",
                    "scripts",
                    ".serverless",
                    "*.pyc",
                    "__pycache__",
                    "terraform",
                    "cloudformation",
                    "cdk",
                ],
            ),
            timeout=Duration.seconds(30),
            memory_size=128,
        )

        action_handler = lambda_.Function(
            self,
            "ActionHandler",
            function_name=f"{api_name}-actionHandler",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="handler.handler",
            code=lambda_.Code.from_asset(
                str(project_dir),
                exclude=[
                    "node_modules",
                    "scripts",
                    ".serverless",
                    "*.pyc",
                    "__pycache__",
                    "terraform",
                    "cloudformation",
                    "cdk",
                ],
            ),
            timeout=Duration.seconds(30),
            memory_size=128,
        )

        # WebSocket API
        websocket_api = apigwv2.WebSocketApi(
            self,
            "WebSocketApi",
            api_name=api_name,
            route_selection_expression="$request.body.action",
            connect_route_options=apigwv2.WebSocketRouteOptions(
                integration=apigwv2_integrations.WebSocketLambdaIntegration(
                    "ConnectIntegration", connection_handler
                )
            ),
            disconnect_route_options=apigwv2.WebSocketRouteOptions(
                integration=apigwv2_integrations.WebSocketLambdaIntegration(
                    "DisconnectIntegration", connection_handler
                )
            ),
            default_route_options=apigwv2.WebSocketRouteOptions(
                integration=apigwv2_integrations.WebSocketLambdaIntegration(
                    "DefaultIntegration", default_handler
                ),
                return_response=True,
            ),
        )

        # Custom route for test-action
        websocket_api.add_route(
            "test-action",
            integration=apigwv2_integrations.WebSocketLambdaIntegration(
                "ActionIntegration", action_handler
            ),
            return_response=True,
        )

        # WebSocket Stage
        stage = apigwv2.WebSocketStage(
            self,
            "ProdStage",
            web_socket_api=websocket_api,
            stage_name="prod",
            auto_deploy=True,
        )

        # Outputs
        CfnOutput(self, "ApiId", value=websocket_api.api_id)
        CfnOutput(self, "ApiEndpoint", value=websocket_api.api_endpoint)
        CfnOutput(self, "StageName", value=stage.stage_name)
        CfnOutput(
            self, "ConnectionHandlerName", value=connection_handler.function_name
        )
        CfnOutput(self, "DefaultHandlerName", value=default_handler.function_name)
        CfnOutput(self, "ActionHandlerName", value=action_handler.function_name)


app = cdk.App()
ApiGwWebsocketsStack(
    app,
    "ApiGwWebsocketsStack",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT", "000000000000"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    ),
)
app.synth()
