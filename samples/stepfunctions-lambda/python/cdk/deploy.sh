#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="StepFunctionsLambdaStack"

echo "Deploying Step Functions Lambda via CDK"

cd "$SCRIPT_DIR"

if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

if command -v awslocal &> /dev/null; then
    AWS="awslocal"
else
    AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"
fi

echo "Step 1: Installing CDK dependencies..."
uv pip install --system -r requirements.txt --quiet 2>/dev/null || true

echo "Step 2: Bootstrapping CDK..."
$CDK bootstrap --quiet 2>/dev/null || true

echo "Step 3: Deploying CDK stack..."
$CDK deploy --require-approval never --outputs-file cdk-outputs.json

echo "Step 4: Extracting outputs..."
ADAM_FUNCTION=$(jq -r ".$STACK_NAME.AdamFunctionOutput" cdk-outputs.json)
ADAM_ARN=$(jq -r ".$STACK_NAME.AdamArnOutput" cdk-outputs.json)
COLE_FUNCTION=$(jq -r ".$STACK_NAME.ColeFunctionOutput" cdk-outputs.json)
COLE_ARN=$(jq -r ".$STACK_NAME.ColeArnOutput" cdk-outputs.json)
COMBINE_FUNCTION=$(jq -r ".$STACK_NAME.CombineFunctionOutput" cdk-outputs.json)
COMBINE_ARN=$(jq -r ".$STACK_NAME.CombineArnOutput" cdk-outputs.json)
STATE_MACHINE_NAME=$(jq -r ".$STACK_NAME.StateMachineNameOutput" cdk-outputs.json)
STATE_MACHINE_ARN=$(jq -r ".$STACK_NAME.StateMachineArnOutput" cdk-outputs.json)

cat > "$SCRIPT_DIR/../scripts/.env" << EOF
ADAM_FUNCTION=$ADAM_FUNCTION
ADAM_ARN=$ADAM_ARN
COLE_FUNCTION=$COLE_FUNCTION
COLE_ARN=$COLE_ARN
COMBINE_FUNCTION=$COMBINE_FUNCTION
COMBINE_ARN=$COMBINE_ARN
STATE_MACHINE_NAME=$STATE_MACHINE_NAME
STATE_MACHINE_ARN=$STATE_MACHINE_ARN
REGION=us-east-1
EOF

echo ""
echo "Deployment complete!"
echo "  State Machine: $STATE_MACHINE_NAME"
echo "  Adam Function: $ADAM_FUNCTION"
echo "  Cole Function: $COLE_FUNCTION"
echo "  Combine Function: $COMBINE_FUNCTION"
