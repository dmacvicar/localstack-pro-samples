#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying API Gateway WebSockets Sample via Terraform"

cd "$SCRIPT_DIR"

if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    TF="terraform"
fi

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

echo "Step 1: Initializing Terraform..."
$TF init -input=false

echo "Step 2: Deploying WebSocket API and Lambda functions..."
$TF apply -auto-approve -input=false

WS_API_ID=$($TF output -raw api_id)
WS_ENDPOINT=$($TF output -raw api_endpoint)
STAGE=$($TF output -raw stage)

echo "Step 3: Waiting for functions to be active..."
MAX_ATTEMPTS=30

for HANDLER in connectionHandler defaultHandler actionHandler; do
    FUNCTION_NAME="apigw-websockets-tf-$HANDLER"
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
