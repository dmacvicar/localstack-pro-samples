#!/bin/bash
set -euo pipefail

# =============================================================================
# Web App DynamoDB - Deployment Script
# AWS equivalent of Azure web-app-cosmosdb-nosql-api
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"

# Configuration
PREFIX="local"
SUFFIX="$(date +%s)"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID="000000000000"

TABLE_NAME="${PREFIX}-items-${SUFFIX}"
FUNCTION_NAME="${PREFIX}-webapp-dynamodb-${SUFFIX}"

# Determine CLI to use
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
TABLE_NAME=$TABLE_NAME
FUNCTION_NAME=$FUNCTION_NAME
REGION=$REGION
EOF

# Create IAM role
echo "Creating IAM role..."
ROLE_NAME="${PREFIX}-lambda-role-${SUFFIX}"
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"

$AWS iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    --region "$REGION" > /dev/null 2>&1 || true

# Create DynamoDB table
echo "Creating DynamoDB table: $TABLE_NAME"
$AWS dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" > /dev/null

# Wait for table to be active
echo "Waiting for table to be active..."
$AWS dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$REGION"

# Package Lambda function
echo "Packaging Lambda function..."
PACKAGE_DIR=$(mktemp -d)
cp "$SRC_DIR/app.py" "$PACKAGE_DIR/handler.py"
cd "$PACKAGE_DIR"
zip -r function.zip handler.py
cd - > /dev/null

# Create Lambda function
echo "Creating Lambda function: $FUNCTION_NAME"
$AWS lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime python3.12 \
    --handler handler.handler \
    --role "$ROLE_ARN" \
    --zip-file "fileb://$PACKAGE_DIR/function.zip" \
    --environment "Variables={TABLE_NAME=$TABLE_NAME}" \
    --timeout 30 \
    --region "$REGION"

# Get Lambda ARN
LAMBDA_ARN=$($AWS lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --query 'Configuration.FunctionArn' \
    --output text \
    --region "$REGION")

echo "LAMBDA_ARN=$LAMBDA_ARN" >> "$SCRIPT_DIR/.env"

# Create Function URL
echo "Creating Function URL..."
FUNCTION_URL=$($AWS lambda create-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --auth-type NONE \
    --query 'FunctionUrl' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$FUNCTION_URL" ]]; then
    echo "FUNCTION_URL=$FUNCTION_URL" >> "$SCRIPT_DIR/.env"

    $AWS lambda add-permission \
        --function-name "$FUNCTION_NAME" \
        --statement-id "FunctionURLAllowPublicAccess" \
        --action "lambda:InvokeFunctionUrl" \
        --principal "*" \
        --function-url-auth-type NONE \
        --region "$REGION" > /dev/null 2>&1 || true
fi

# Cleanup
rm -rf "$PACKAGE_DIR"

echo ""
echo "Deployment complete!"
echo "  DynamoDB Table: $TABLE_NAME"
echo "  Lambda Function: $FUNCTION_NAME"
[[ -n "${FUNCTION_URL:-}" ]] && echo "  Function URL: $FUNCTION_URL"
