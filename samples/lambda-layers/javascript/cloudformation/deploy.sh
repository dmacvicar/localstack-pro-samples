#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="lambda-layers-cfn-stack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Lambda Layers Sample via CloudFormation"

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

FUNCTION_NAME="lambda-layers-cfn"
LAYER_NAME="shared-layer-cfn"
S3_BUCKET="lambda-layers-cfn-deployment"

echo "Step 1: Creating deployment bucket..."
$AWS s3api create-bucket --bucket "$S3_BUCKET" --region "$REGION" 2>/dev/null || true

echo "Step 2: Packaging layer..."
cd "$PROJECT_DIR"
LAYER_ZIP="$SCRIPT_DIR/layer.zip"
(cd layer && zip -r "$LAYER_ZIP" .)
$AWS s3 cp "$LAYER_ZIP" "s3://$S3_BUCKET/layer.zip" --region "$REGION"

echo "Step 3: Packaging function..."
FUNCTION_ZIP="$SCRIPT_DIR/function.zip"
zip -j "$FUNCTION_ZIP" handler.js
$AWS s3 cp "$FUNCTION_ZIP" "s3://$S3_BUCKET/function.zip" --region "$REGION"

echo "Step 4: Deploying CloudFormation stack..."
cd "$SCRIPT_DIR"
$AWS cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file template.yml \
    --parameter-overrides \
        "FunctionName=$FUNCTION_NAME" \
        "LayerName=$LAYER_NAME" \
        "S3Bucket=$S3_BUCKET" \
        "LayerS3Key=layer.zip" \
        "FunctionS3Key=function.zip" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --no-fail-on-empty-changeset

echo "Step 5: Waiting for function to be active..."
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

# Get outputs
FUNCTION_ARN=$($AWS lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --query 'Configuration.FunctionArn' \
    --output text 2>/dev/null || echo "")

LAYER_ARN=$($AWS lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --query 'Configuration.Layers[0].Arn' \
    --output text 2>/dev/null || echo "")

# Save outputs for tests
cat > "$PROJECT_DIR/scripts/.env" << EOF
REGION=$REGION
FUNCTION_NAME=$FUNCTION_NAME
FUNCTION_ARN=$FUNCTION_ARN
LAYER_ARN=$LAYER_ARN
LAYER_NAME=$LAYER_NAME
EOF

# Clean up local zips
rm -f "$LAYER_ZIP" "$FUNCTION_ZIP"

echo ""
echo "Deployment complete!"
echo "  Function: $FUNCTION_NAME"
echo "  Layer: $LAYER_ARN"
