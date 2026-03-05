"""
Tests for apigw-websockets sample (JavaScript).

Run with:
    uv run pytest samples/apigw-websockets/javascript/ -v
"""

import json
from pathlib import Path

import pytest

# Sample configuration
SAMPLE_NAME = "apigw-websockets"
LANGUAGE = "javascript"
SAMPLE_DIR = Path(__file__).parent

# Function name patterns per IaC method
FUNCTION_NAME_PATTERNS = {
    "scripts": "apigw-websockets-sample-{stage}-{handler}",
    "terraform": "apigw-websockets-tf-{handler}",
    "cloudformation": "apigw-websockets-cfn-{handler}",
    "cdk": "apigw-websockets-cdk-{handler}",
}


def get_iac_methods():
    """Discover available IaC methods for this sample."""
    methods = []
    if (SAMPLE_DIR / "scripts" / "deploy.sh").exists():
        methods.append("scripts")
    for iac in ["terraform", "cloudformation", "cdk"]:
        if (SAMPLE_DIR / iac / "deploy.sh").exists():
            methods.append(iac)
    return methods


def get_function_name(iac_method: str, handler: str, stage: str = "local") -> str:
    """Get the function name for the given IaC method and handler."""
    pattern = FUNCTION_NAME_PATTERNS.get(iac_method, FUNCTION_NAME_PATTERNS["scripts"])
    return pattern.format(stage=stage, handler=handler)


@pytest.fixture(scope="module", params=get_iac_methods())
def deployed_env(request, wait_for):
    """Deploy the sample with each IaC method and return env vars."""
    from conftest import run_deploy, get_deploy_script_path

    iac_method = request.param

    script_path = get_deploy_script_path(SAMPLE_NAME, LANGUAGE, iac_method)
    if not script_path.exists():
        pytest.skip(f"Deploy script not found for {iac_method}")

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method)
    env["IAC_METHOD"] = iac_method

    return env


class TestApiGwWebsockets:
    """Test suite for API Gateway WebSockets sample."""

    def test_websocket_api_exists(self, deployed_env, aws_clients):
        """WebSocket API should exist."""
        api_id = deployed_env["WS_API_ID"]
        response = aws_clients.apigatewayv2_client.get_api(ApiId=api_id)
        assert response["ProtocolType"] == "WEBSOCKET"

    def test_connection_handler_active(self, deployed_env, aws_clients):
        """Connection handler Lambda should be active."""
        iac_method = deployed_env.get("IAC_METHOD", "scripts")
        stage = deployed_env.get("STAGE", "local")
        function_name = get_function_name(iac_method, "connectionHandler", stage)
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_default_handler_active(self, deployed_env, aws_clients):
        """Default handler Lambda should be active."""
        iac_method = deployed_env.get("IAC_METHOD", "scripts")
        stage = deployed_env.get("STAGE", "local")
        function_name = get_function_name(iac_method, "defaultHandler", stage)
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_action_handler_active(self, deployed_env, aws_clients):
        """Action handler Lambda should be active."""
        iac_method = deployed_env.get("IAC_METHOD", "scripts")
        stage = deployed_env.get("STAGE", "local")
        function_name = get_function_name(iac_method, "actionHandler", stage)
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_routes_configured(self, deployed_env, aws_clients):
        """WebSocket routes should be configured."""
        api_id = deployed_env["WS_API_ID"]
        response = aws_clients.apigatewayv2_client.get_routes(ApiId=api_id)
        route_keys = [r["RouteKey"] for r in response.get("Items", [])]

        expected_routes = ["$connect", "$disconnect", "$default", "test-action"]
        for route in expected_routes:
            assert route in route_keys, f"Route '{route}' not found"

    def test_websocket_connection(self, deployed_env):
        """WebSocket should accept connections and respond to messages."""
        import asyncio

        try:
            import websockets
        except ImportError:
            pytest.skip("websockets library not available")

        ws_endpoint = deployed_env["WS_ENDPOINT"]

        async def test_ws():
            try:
                async with websockets.connect(
                    ws_endpoint, close_timeout=5, open_timeout=5
                ) as ws:
                    # Send test message
                    msg = {"action": "test-action", "data": "hello"}
                    await ws.send(json.dumps(msg))

                    # Get response
                    response = await asyncio.wait_for(ws.recv(), timeout=5)
                    result = json.loads(response)

                    # Verify response
                    return (
                        result.get("data") == "hello"
                        or result.get("requestContext", {}).get("routeKey")
                        == "test-action"
                    )
            except Exception:
                return False

        result = asyncio.run(test_ws())
        assert result, "WebSocket message round-trip failed"
