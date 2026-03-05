#!/bin/bash
set -euo pipefail

# =============================================================================
# Web App RDS - Deployment Script
# AWS equivalent of Azure web-app-sql-database
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"

# Configuration
PREFIX="local"
SUFFIX="$(date +%s)"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID="000000000000"

DB_INSTANCE_ID="${PREFIX}-postgres-${SUFFIX}"
DB_NAME="appdb"
DB_USER="admin"
DB_PASSWORD="localstack123"
FUNCTION_NAME="${PREFIX}-webapp-rds-${SUFFIX}"

# Determine CLI to use
if command -v awslocal &> /dev/null; then
    AWS="awslocal"
    echo "Using awslocal for LocalStack environment."
else
    AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"
    echo "Using AWS CLI with LocalStack endpoint."
fi

# Save config for test script
cat > "$SCRIPT_DIR/.env" << EOF
PREFIX=$PREFIX
SUFFIX=$SUFFIX
DB_INSTANCE_ID=$DB_INSTANCE_ID
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
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

# Create RDS PostgreSQL instance
echo "Creating RDS PostgreSQL instance: $DB_INSTANCE_ID"
$AWS rds create-db-instance \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --engine-version "13.4" \
    --master-username "$DB_USER" \
    --master-user-password "$DB_PASSWORD" \
    --db-name "$DB_NAME" \
    --allocated-storage 20 \
    --region "$REGION" > /dev/null 2>&1 || echo "RDS instance may already exist"

# Wait for RDS instance to be available
echo "Waiting for RDS instance to be available..."
MAX_ATTEMPTS=30
ATTEMPT=1
DB_HOST=""

while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
    STATUS=$($AWS rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "pending")

    if [[ "$STATUS" == "available" ]]; then
        DB_HOST=$($AWS rds describe-db-instances \
            --db-instance-identifier "$DB_INSTANCE_ID" \
            --query 'DBInstances[0].Endpoint.Address' \
            --output text \
            --region "$REGION")
        DB_PORT=$($AWS rds describe-db-instances \
            --db-instance-identifier "$DB_INSTANCE_ID" \
            --query 'DBInstances[0].Endpoint.Port' \
            --output text \
            --region "$REGION")
        echo "RDS instance ready: $DB_HOST:$DB_PORT"
        break
    fi

    echo "  Attempt $ATTEMPT: Status = $STATUS"
    sleep 2
    ((ATTEMPT++))
done

if [[ -z "$DB_HOST" ]]; then
    echo "Warning: Could not get RDS endpoint, using localhost for simulated mode"
    DB_HOST="localhost"
    DB_PORT="5432"
fi

echo "DB_HOST=$DB_HOST" >> "$SCRIPT_DIR/.env"
echo "DB_PORT=${DB_PORT:-5432}" >> "$SCRIPT_DIR/.env"

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
    --environment "Variables={DB_HOST=$DB_HOST,DB_PORT=${DB_PORT:-5432},DB_NAME=$DB_NAME,DB_USER=$DB_USER,DB_PASSWORD=$DB_PASSWORD}" \
    --timeout 30 \
    --region "$REGION"

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
echo "  RDS Instance: $DB_INSTANCE_ID"
echo "  Database: $DB_NAME"
echo "  Lambda Function: $FUNCTION_NAME"
[[ -n "${FUNCTION_URL:-}" ]] && echo "  Function URL: $FUNCTION_URL"
