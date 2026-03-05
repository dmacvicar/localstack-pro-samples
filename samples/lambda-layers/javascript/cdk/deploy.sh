#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="LambdaLayersStack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Lambda Layers Sample via CDK"

cd "$SCRIPT_DIR"

if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

echo "Step 1: Installing CDK dependencies..."
uv pip install --system -r requirements.txt --quiet 2>/dev/null || true

echo "Step 2: Bootstrapping CDK..."
$CDK bootstrap --quiet 2>/dev/null || true

echo "Step 3: Deploying stack..."
$CDK deploy --require-approval never --outputs-file cdk-outputs.json 2>&1 | tail -10

# Get outputs
FUNCTION_NAME=$(jq -r ".$STACK_NAME.FunctionName" cdk-outputs.json)
FUNCTION_ARN=$(jq -r ".$STACK_NAME.FunctionArn" cdk-outputs.json)
LAYER_ARN=$(jq -r ".$STACK_NAME.LayerArn" cdk-outputs.json)
LAYER_NAME=$(jq -r ".$STACK_NAME.LayerName" cdk-outputs.json)

echo "Step 4: Waiting for function to be active..."
MAX_ATTEMPTS=30
ATTEMPT=1

while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
    STATE=$($AWS lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" \
        --query 'Configuration.State' \
        --output text 2>/dev/null || echo "Pending")

    if [[ "$STATE" == "Active" ]]; then
        echo "  Function is active"
        break
    fi
    echo "  State: $STATE (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done

# Save outputs for tests
cat > "$PROJECT_DIR/scripts/.env" << EOF
REGION=$REGION
FUNCTION_NAME=$FUNCTION_NAME
FUNCTION_ARN=$FUNCTION_ARN
LAYER_ARN=$LAYER_ARN
LAYER_NAME=$LAYER_NAME
EOF

echo ""
echo "Deployment complete!"
echo "  Function: $FUNCTION_NAME"
echo "  Layer: $LAYER_ARN"
