#!/bin/bash
set -euo pipefail

# =============================================================================
# Lambda Function URLs - CloudFormation Deployment
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="lambda-function-url-stack"
FUNCTION_NAME="lambda-function-url-cfn"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Lambda Function URL Sample via CloudFormation"
echo "  Stack: $STACK_NAME"
echo "  Region: $REGION"

# Use aws CLI directly with endpoint-url to avoid awslocal --s3-endpoint-url bug
AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

cd "$SCRIPT_DIR"

# Deploy CloudFormation stack
echo ""
echo "Step 1: Deploying CloudFormation stack..."
$AWS cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file template.yml \
    --parameter-overrides "FunctionName=$FUNCTION_NAME" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --no-fail-on-empty-changeset

# Wait for stack to complete
echo "Step 2: Waiting for stack to complete..."
$AWS cloudformation wait stack-create-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION" 2>/dev/null || \
$AWS cloudformation wait stack-update-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION" 2>/dev/null || true

# Extract outputs
echo "Step 3: Extracting outputs..."
STACK_OUTPUTS=$($AWS cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs' \
    --region "$REGION" 2>/dev/null)

FUNCTION_NAME=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionName") | .OutputValue')
FUNCTION_URL=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionUrl") | .OutputValue')
LAMBDA_ARN=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionArn") | .OutputValue')

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
