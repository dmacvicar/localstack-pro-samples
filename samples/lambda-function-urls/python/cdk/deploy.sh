#!/bin/bash
set -euo pipefail

# =============================================================================
# Lambda Function URLs - CDK Deployment
#
# Uses cdklocal (aws-cdk-local) to deploy to LocalStack
# Install: npm install -g aws-cdk-local aws-cdk
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="LambdaFunctionUrlStack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Lambda Function URL Sample via CDK"
echo "  Stack: $STACK_NAME"
echo "  Region: $REGION"

cd "$SCRIPT_DIR"

# Determine CDK CLI to use
if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    echo "Warning: cdklocal not found, using cdk (may not work with LocalStack)"
    CDK="cdk"
fi

# Determine AWS CLI to use
if command -v awslocal &> /dev/null; then
    AWS="awslocal"
else
    AWS="aws --endpoint-url=http://localhost:4566"
fi

# Install Python dependencies
echo ""
echo "Step 1: Installing CDK dependencies..."
uv pip install --system -r requirements.txt --quiet 2>/dev/null || true

# Bootstrap CDK (if needed)
echo "Step 2: Bootstrapping CDK..."
$CDK bootstrap --quiet 2>/dev/null || true

# Deploy stack
echo "Step 3: Deploying CDK stack..."
$CDK deploy --require-approval never --outputs-file cdk-outputs.json

# Extract outputs
echo "Step 4: Extracting outputs..."
if [[ -f cdk-outputs.json ]]; then
    FUNCTION_NAME=$(jq -r ".$STACK_NAME.FunctionName" cdk-outputs.json)
    FUNCTION_URL=$(jq -r ".$STACK_NAME.FunctionUrl" cdk-outputs.json)
    LAMBDA_ARN=$(jq -r ".$STACK_NAME.FunctionArn" cdk-outputs.json)
else
    # Fallback: get from CloudFormation
    STACK_OUTPUTS=$($AWS cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs' \
        --region "$REGION" 2>/dev/null)

    FUNCTION_NAME=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionName") | .OutputValue')
    FUNCTION_URL=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionUrl") | .OutputValue')
    LAMBDA_ARN=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionArn") | .OutputValue')
fi

# Save config for test script (shared with scripts/)
cat > "$SCRIPT_DIR/../scripts/.env" << EOF
FUNCTION_NAME=$FUNCTION_NAME
FUNCTION_URL=$FUNCTION_URL
LAMBDA_ARN=$LAMBDA_ARN
REGION=$REGION
STACK_NAME=$STACK_NAME
EOF

echo ""
echo "Deployment complete!"
echo "  Function Name: $FUNCTION_NAME"
echo "  Function URL: $FUNCTION_URL"
echo ""
echo "Run tests with: ../scripts/test.sh"
