#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="ApiGwWebsocketsStack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying API Gateway WebSockets Sample via CDK"

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
WS_API_ID=$(jq -r ".$STACK_NAME.ApiId" cdk-outputs.json)
WS_ENDPOINT=$(jq -r ".$STACK_NAME.ApiEndpoint" cdk-outputs.json)
STAGE=$(jq -r ".$STACK_NAME.StageName" cdk-outputs.json)

echo "Step 4: Waiting for functions to be active..."
MAX_ATTEMPTS=30

for HANDLER in connectionHandler defaultHandler actionHandler; do
    FUNCTION_NAME="apigw-websockets-cdk-$HANDLER"
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

# Save outputs for tests
cat > "$PROJECT_DIR/scripts/.env" << EOF
REGION=$REGION
STAGE=$STAGE
WS_API_ID=$WS_API_ID
WS_ENDPOINT=$WS_ENDPOINT
EOF

echo ""
echo "Deployment complete!"
echo "  WebSocket API ID: $WS_API_ID"
echo "  WebSocket Endpoint: $WS_ENDPOINT"
