#!/bin/bash
set -euo pipefail

# =============================================================================
# Lambda Layers - Deployment Script (JavaScript/Serverless)
#
# Deploys Lambda function with shared layer using Serverless Framework.
# Ported from: https://github.com/localstack-samples/localstack-pro-samples/tree/master/serverless-lambda-layers
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."

# Configuration
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
STAGE="local"

# Determine CLI to use
if command -v awslocal &> /dev/null; then
    AWS="awslocal"
else
    AWS="aws --endpoint-url=http://localhost:4566"
fi

echo "Deploying Lambda Layers Sample (Serverless Framework)"
echo "  Region: $REGION"
echo "  Stage: $STAGE"
echo ""

# Install dependencies if needed
cd "$PROJECT_DIR"
if [[ ! -d "node_modules" ]]; then
    echo "Installing dependencies..."
    npm install
fi

# Create deployment bucket
echo "Creating deployment bucket..."
$AWS s3api create-bucket --bucket lambda-layers-deployment --region "$REGION" 2>/dev/null || true

# Deploy with Serverless
echo "Deploying with Serverless Framework..."
npx serverless deploy --stage "$STAGE" --region "$REGION"

# Get deployed resources info
echo ""
echo "Getting deployment info..."

FUNCTION_NAME="lambda-layers-sample-$STAGE-hello"

# Wait for function to be active
echo "Waiting for function to be active..."
for i in {1..30}; do
    STATE=$($AWS lambda get-function --function-name "$FUNCTION_NAME" --query 'Configuration.State' --output text --region "$REGION" 2>/dev/null || echo "Pending")
    if [[ "$STATE" == "Active" ]]; then
        echo "Function is active"
        break
    fi
    sleep 2
done

# Get function info
FUNCTION_ARN=$($AWS lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --query 'Configuration.FunctionArn' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

LAYERS=$($AWS lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --query 'Configuration.Layers[].Arn' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

# Save config for test script
cat > "$SCRIPT_DIR/.env" << EOF
REGION=$REGION
STAGE=$STAGE
FUNCTION_NAME=$FUNCTION_NAME
FUNCTION_ARN=$FUNCTION_ARN
LAYERS=$LAYERS
EOF

echo ""
echo "Deployment complete!"
echo "  Function: $FUNCTION_NAME"
echo "  Layers: $LAYERS"
