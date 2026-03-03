#!/bin/bash
set -euo pipefail

# =============================================================================
# Lambda CloudFront - Deployment Script
# AWS equivalent of Azure function-app-front-door
#
# Note: Uses Lambda Function URLs as the entry point. CloudFront distribution
# can be added in front of the Function URL in production AWS.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"

# Configuration
PREFIX="local"
SUFFIX="$(date +%s)"
FUNCTION_NAME="${PREFIX}-cloudfront-handler-${SUFFIX}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID="000000000000"

# Determine CLI to use (LocalStack vs AWS)
if command -v awslocal &> /dev/null; then
    AWS="awslocal"
    echo "Using awslocal for LocalStack environment."
else
    AWS="aws --endpoint-url=http://localhost:4566"
    echo "Using AWS CLI with LocalStack endpoint."
fi

# Save config for test script
cat > "$SCRIPT_DIR/.env" << EOF
PREFIX=$PREFIX
SUFFIX=$SUFFIX
FUNCTION_NAME=$FUNCTION_NAME
REGION=$REGION
EOF

# Package Lambda function
echo "Packaging Lambda function..."
PACKAGE_DIR=$(mktemp -d)
cp "$SRC_DIR/handler.py" "$PACKAGE_DIR/"
cd "$PACKAGE_DIR"
zip -r function.zip handler.py
cd - > /dev/null

# Create IAM role for Lambda
echo "Creating IAM role..."
ROLE_NAME="${PREFIX}-lambda-role-${SUFFIX}"
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"

$AWS iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    --region "$REGION" > /dev/null 2>&1 || true

echo "ROLE_ARN=$ROLE_ARN" >> "$SCRIPT_DIR/.env"

# Create Lambda function
echo "Creating Lambda function: $FUNCTION_NAME"
$AWS lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime python3.12 \
    --handler handler.handler \
    --role "$ROLE_ARN" \
    --zip-file "fileb://$PACKAGE_DIR/function.zip" \
    --region "$REGION"

# Get Lambda ARN
LAMBDA_ARN=$($AWS lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --query 'Configuration.FunctionArn' \
    --output text \
    --region "$REGION")

echo "Lambda ARN: $LAMBDA_ARN"
echo "LAMBDA_ARN=$LAMBDA_ARN" >> "$SCRIPT_DIR/.env"

# Create Lambda Function URL
echo "Creating Lambda Function URL..."
FUNCTION_URL=$($AWS lambda create-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --auth-type NONE \
    --query 'FunctionUrl' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$FUNCTION_URL" ]]; then
    echo "Function URL: $FUNCTION_URL"
    echo "FUNCTION_URL=$FUNCTION_URL" >> "$SCRIPT_DIR/.env"
fi

# Add resource-based policy for public access
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
echo "  Function: $FUNCTION_NAME"
[[ -n "${FUNCTION_URL:-}" ]] && echo "  Function URL: $FUNCTION_URL"
echo ""
echo "Note: In production AWS, add CloudFront distribution in front of the Function URL"
