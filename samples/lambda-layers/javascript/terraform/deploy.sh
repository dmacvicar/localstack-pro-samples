#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Lambda Layers Sample via Terraform"

cd "$SCRIPT_DIR"

if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    TF="terraform"
fi

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

echo "Step 1: Initializing Terraform..."
$TF init -input=false

echo "Step 2: Deploying Lambda Layer and Function..."
$TF apply -auto-approve -input=false

FUNCTION_NAME=$($TF output -raw function_name)
FUNCTION_ARN=$($TF output -raw function_arn)
LAYER_ARN=$($TF output -raw layer_arn)
LAYER_NAME=$($TF output -raw layer_name)

echo "Step 3: Waiting for function to be active..."
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
