#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="apigw-websockets-cfn-stack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying API Gateway WebSockets Sample via CloudFormation"

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

API_NAME="apigw-websockets-cfn"
S3_BUCKET="apigw-websockets-cfn-deployment"

echo "Step 1: Creating deployment bucket..."
$AWS s3api create-bucket --bucket "$S3_BUCKET" --region "$REGION" 2>/dev/null || true

echo "Step 2: Packaging function..."
cd "$PROJECT_DIR"
FUNCTION_ZIP="$SCRIPT_DIR/function.zip"
zip -j "$FUNCTION_ZIP" handler.js
$AWS s3 cp "$FUNCTION_ZIP" "s3://$S3_BUCKET/function.zip" --region "$REGION"

echo "Step 3: Deploying CloudFormation stack..."
cd "$SCRIPT_DIR"
$AWS cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file template.yml \
    --parameter-overrides \
        "ApiName=$API_NAME" \
        "S3Bucket=$S3_BUCKET" \
        "FunctionS3Key=function.zip" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --no-fail-on-empty-changeset

echo "Step 4: Waiting for functions to be active..."
MAX_ATTEMPTS=30

for HANDLER in connectionHandler defaultHandler actionHandler; do
    FUNCTION_NAME="$API_NAME-$HANDLER"
    ATTEMPT=1
    while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
        STATE=$($AWS lambda get-function \
            --function-name "$FUNCTION_NAME" \
            --region "$REGION" \
            --query 'Configuration.State' \
            --output text 2>/dev/null || echo "Pending")

        if [[ "$STATE" == "Active" ]]; then
            echo "  $HANDLER is active"
            break
        fi
        sleep 2
        ATTEMPT=$((ATTEMPT + 1))
    done
done

# Get outputs
WS_API_ID=$($AWS apigatewayv2 get-apis \
    --query "Items[?Name=='$API_NAME'].ApiId | [0]" \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

WS_ENDPOINT=$($AWS apigatewayv2 get-apis \
    --query "Items[?Name=='$API_NAME'].ApiEndpoint | [0]" \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

# Save outputs for tests
cat > "$PROJECT_DIR/scripts/.env" << EOF
REGION=$REGION
STAGE=prod
WS_API_ID=$WS_API_ID
WS_ENDPOINT=$WS_ENDPOINT
EOF

# Clean up local zip
rm -f "$FUNCTION_ZIP"

echo ""
echo "Deployment complete!"
echo "  WebSocket API ID: $WS_API_ID"
echo "  WebSocket Endpoint: $WS_ENDPOINT"
