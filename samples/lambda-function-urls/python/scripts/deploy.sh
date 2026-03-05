#!/bin/bash
set -euo pipefail

# =============================================================================
# Lambda Function URLs - Deployment Script (Python)
#
# Demonstrates Lambda Function URLs - HTTPS endpoints directly on Lambda
# functions without requiring API Gateway.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"

# Configuration
PREFIX="local"
SUFFIX="$(date +%s)"
FUNCTION_NAME="${PREFIX}-function-url-${SUFFIX}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID="000000000000"

# Determine CLI to use
if command -v awslocal &> /dev/null; then
    AWS="awslocal"
else
    AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"
fi

echo "Deploying Lambda Function URL Sample (Python)"
echo "  Function: $FUNCTION_NAME"
echo "  Region: $REGION"

# Save config for test script
cat > "$SCRIPT_DIR/.env" << EOF
PREFIX=$PREFIX
SUFFIX=$SUFFIX
FUNCTION_NAME=$FUNCTION_NAME
REGION=$REGION
ACCOUNT_ID=$ACCOUNT_ID
EOF

# Package Lambda function
echo ""
echo "Step 1: Packaging Lambda function..."
PACKAGE_DIR=$(mktemp -d)
cp "$SRC_DIR/handler.py" "$PACKAGE_DIR/"
cd "$PACKAGE_DIR"
zip -q -r function.zip handler.py
cd - > /dev/null

# Create IAM role
echo "Step 2: Creating IAM role..."
ROLE_NAME="${PREFIX}-lambda-role-${SUFFIX}"
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"

$AWS iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }' \
    --region "$REGION" > /dev/null 2>&1 || true

echo "ROLE_NAME=$ROLE_NAME" >> "$SCRIPT_DIR/.env"
echo "ROLE_ARN=$ROLE_ARN" >> "$SCRIPT_DIR/.env"

# Create Lambda function
echo "Step 3: Creating Lambda function..."
$AWS lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime python3.12 \
    --handler handler.handler \
    --role "$ROLE_ARN" \
    --zip-file "fileb://$PACKAGE_DIR/function.zip" \
    --region "$REGION" > /dev/null

# Wait for function to be active
echo "Step 4: Waiting for function to be active..."
$AWS lambda wait function-active-v2 \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" 2>/dev/null || sleep 2

# Get Lambda ARN
LAMBDA_ARN=$($AWS lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --query 'Configuration.FunctionArn' \
    --output text \
    --region "$REGION")

echo "  Lambda ARN: $LAMBDA_ARN"
echo "LAMBDA_ARN=$LAMBDA_ARN" >> "$SCRIPT_DIR/.env"

# Create Function URL
echo "Step 5: Creating Lambda Function URL..."
FUNCTION_URL=$($AWS lambda create-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --auth-type NONE \
    --query 'FunctionUrl' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$FUNCTION_URL" ]]; then
    echo "  Function URL: $FUNCTION_URL"
    echo "FUNCTION_URL=$FUNCTION_URL" >> "$SCRIPT_DIR/.env"
else
    echo "  Warning: Function URL creation failed (may not be supported)"
fi

# Add permission for public access
echo "Step 6: Adding public access permission..."
$AWS lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --statement-id "FunctionURLAllowPublicAccess" \
    --action "lambda:InvokeFunctionUrl" \
    --principal "*" \
    --function-url-auth-type NONE \
    --region "$REGION" > /dev/null 2>&1 || true

# Cleanup
rm -rf "$PACKAGE_DIR"

echo ""
echo "Deployment complete!"
echo "  Function Name: $FUNCTION_NAME"
echo "  Function ARN: $LAMBDA_ARN"
[[ -n "${FUNCTION_URL:-}" ]] && echo "  Function URL: $FUNCTION_URL"
