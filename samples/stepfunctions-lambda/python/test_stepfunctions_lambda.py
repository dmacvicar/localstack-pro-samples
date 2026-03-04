"""
Tests for stepfunctions-lambda sample.

Run with:
    uv run pytest samples/stepfunctions-lambda/python/ -v
"""

import json
from pathlib import Path

import pytest

# Sample configuration
SAMPLE_NAME = "stepfunctions-lambda"
LANGUAGE = "python"
SAMPLE_DIR = Path(__file__).parent


def get_iac_methods():
    """Discover available IaC methods for this sample."""
    methods = []
    if (SAMPLE_DIR / "scripts" / "deploy.sh").exists():
        methods.append("scripts")
    for iac in ["terraform", "cloudformation", "cdk"]:
        if (SAMPLE_DIR / iac / "deploy.sh").exists():
            methods.append(iac)
    return methods


@pytest.fixture(scope="module", params=get_iac_methods())
def deployed_env(request, wait_for):
    """Deploy the sample with each IaC method and return env vars."""
    from conftest import run_deploy, get_deploy_script_path

    iac_method = request.param

    script_path = get_deploy_script_path(SAMPLE_NAME, LANGUAGE, iac_method)
    if not script_path.exists():
        pytest.skip(f"Deploy script not found for {iac_method}")

    env = run_deploy(SAMPLE_NAME, LANGUAGE, iac_method)

    # Wait for all Lambda functions to be active
    for func_key in ["ADAM_FUNCTION", "COLE_FUNCTION", "COMBINE_FUNCTION"]:
        if func_key in env:
            wait_for.lambda_active(env[func_key])

    return env


class TestStepFunctionsLambda:
    """Test suite for Step Functions Lambda sample."""

    def test_adam_function_exists(self, deployed_env, aws_clients):
        """Adam Lambda function should exist and be active."""
        function_name = deployed_env["ADAM_FUNCTION"]
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_cole_function_exists(self, deployed_env, aws_clients):
        """Cole Lambda function should exist and be active."""
        function_name = deployed_env["COLE_FUNCTION"]
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_combine_function_exists(self, deployed_env, aws_clients):
        """Combine Lambda function should exist and be active."""
        function_name = deployed_env["COMBINE_FUNCTION"]
        response = aws_clients.lambda_client.get_function(FunctionName=function_name)
        assert response["Configuration"]["State"] == "Active"

    def test_state_machine_exists(self, deployed_env, aws_clients):
        """State machine should exist and be active."""
        state_machine_arn = deployed_env["STATE_MACHINE_ARN"]
        response = aws_clients.stepfunctions_client.describe_state_machine(
            stateMachineArn=state_machine_arn
        )
        assert response["status"] == "ACTIVE"

    def test_adam_lambda_invocation(self, deployed_env, invoke_lambda):
        """Adam Lambda should extract adam value from input."""
        function_name = deployed_env["ADAM_FUNCTION"]
        response = invoke_lambda(function_name, {
            "input": {"adam": "LocalStack", "cole": "Stack"}
        })
        assert response == "LocalStack"

    def test_cole_lambda_invocation(self, deployed_env, invoke_lambda):
        """Cole Lambda should extract cole value from input."""
        function_name = deployed_env["COLE_FUNCTION"]
        response = invoke_lambda(function_name, {
            "input": {"adam": "LocalStack", "cole": "Stack"}
        })
        assert response == "Stack"

    def test_combine_lambda_invocation(self, deployed_env, invoke_lambda):
        """Combine Lambda should combine inputs."""
        function_name = deployed_env["COMBINE_FUNCTION"]
        response = invoke_lambda(function_name, {
            "input": ["LocalStack", "Stack"]
        })
        assert response == "Together Adam and Cole say 'LocalStack Stack'!!"

    def test_state_machine_execution(self, deployed_env, aws_clients, wait_for):
        """State machine execution should succeed."""
        state_machine_arn = deployed_env["STATE_MACHINE_ARN"]

        execution = aws_clients.stepfunctions_client.start_execution(
            stateMachineArn=state_machine_arn,
            input=json.dumps({"adam": "LocalStack", "cole": "Stack"})
        )

        result = wait_for.sfn_execution_complete(execution["executionArn"])
        assert result["status"] == "SUCCEEDED"

    def test_state_machine_output(self, deployed_env, aws_clients, wait_for):
        """State machine output should match expected format."""
        state_machine_arn = deployed_env["STATE_MACHINE_ARN"]

        execution = aws_clients.stepfunctions_client.start_execution(
            stateMachineArn=state_machine_arn,
            input=json.dumps({"adam": "Hello", "cole": "World"})
        )

        result = wait_for.sfn_execution_complete(execution["executionArn"])
        output = json.loads(result["output"])
        assert output == "Together Adam and Cole say 'Hello World'!!"

    def test_state_machine_parallel_execution(self, deployed_env, aws_clients, wait_for):
        """State machine should use parallel execution for Adam and Cole."""
        state_machine_arn = deployed_env["STATE_MACHINE_ARN"]

        # The state machine definition uses Parallel state for Adam and Cole
        response = aws_clients.stepfunctions_client.describe_state_machine(
            stateMachineArn=state_machine_arn
        )
        definition = json.loads(response["definition"])

        # Verify Parallel state exists
        states = definition.get("States", {})
        has_parallel = any(
            state.get("Type") == "Parallel"
            for state in states.values()
        )
        assert has_parallel, "State machine should have a Parallel state"
