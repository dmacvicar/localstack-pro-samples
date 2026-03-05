#!/bin/bash
set -euo pipefail

# =============================================================================
# API Gateway WebSockets - Deployment Script (JavaScript/Serverless)
#
# Deploys WebSocket API with Lambda handlers using Serverless Framework.
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
    AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"
fi

echo "Deploying API Gateway WebSockets Sample (Serverless Framework)"
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
$AWS s3api create-bucket --bucket apigw-websockets-deployment --region "$REGION" 2>/dev/null || true

# Deploy with Serverless
echo "Deploying with Serverless Framework..."
npx serverless deploy --stage "$STAGE" --region "$REGION"

# Wait for functions to be active
echo ""
echo "Waiting for functions to be active..."
for FUNC in connectionHandler defaultHandler actionHandler; do
    FUNCTION_NAME="apigw-websockets-sample-$STAGE-$FUNC"
    for i in {1..30}; do
        STATE=$($AWS lambda get-function --function-name "$FUNCTION_NAME" --query 'Configuration.State' --output text --region "$REGION" 2>/dev/null || echo "Pending")
        if [[ "$STATE" == "Active" ]]; then
            echo "  $FUNC is active"
            break
        fi
        sleep 2
    done
done

# Get WebSocket API info
echo ""
echo "Getting WebSocket API info..."
# The Serverless Framework creates WebSocket APIs with name pattern: {stage}-{service}-websockets
WS_API_ID=$($AWS apigatewayv2 get-apis --query "Items[?contains(Name, 'apigw-websockets-sample') && ProtocolType=='WEBSOCKET'].ApiId | [0]" --output text --region "$REGION" 2>/dev/null || echo "")
WS_ENDPOINT=$($AWS apigatewayv2 get-apis --query "Items[?contains(Name, 'apigw-websockets-sample') && ProtocolType=='WEBSOCKET'].ApiEndpoint | [0]" --output text --region "$REGION" 2>/dev/null || echo "")

# Save config for test script
cat > "$SCRIPT_DIR/.env" << EOF
REGION=$REGION
STAGE=$STAGE
WS_API_ID=$WS_API_ID
WS_ENDPOINT=$WS_ENDPOINT
EOF

echo ""
echo "Deployment complete!"
echo "  WebSocket API ID: $WS_API_ID"
echo "  WebSocket Endpoint: $WS_ENDPOINT"
