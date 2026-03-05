#!/bin/bash
set -euo pipefail

# =============================================================================
# Lambda S3 HTTP - Deployment Script
# AWS equivalent of Azure function-app-storage-http (gaming scoreboard)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"

# Configuration
PREFIX="local"
SUFFIX="$(date +%s)"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID="000000000000"

TABLE_NAME="${PREFIX}-game-scores-${SUFFIX}"
BUCKET_NAME="${PREFIX}-replays-${SUFFIX}"
QUEUE_NAME="${PREFIX}-score-validation-${SUFFIX}"

HTTP_FUNCTION="${PREFIX}-http-handler-${SUFFIX}"
S3_FUNCTION="${PREFIX}-s3-handler-${SUFFIX}"
SQS_FUNCTION="${PREFIX}-sqs-handler-${SUFFIX}"

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
TABLE_NAME=$TABLE_NAME
BUCKET_NAME=$BUCKET_NAME
QUEUE_NAME=$QUEUE_NAME
HTTP_FUNCTION=$HTTP_FUNCTION
S3_FUNCTION=$S3_FUNCTION
SQS_FUNCTION=$SQS_FUNCTION
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
    --attribute-definitions AttributeName=playerId,AttributeType=S \
    --key-schema AttributeName=playerId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" > /dev/null

# Create S3 bucket
echo "Creating S3 bucket: $BUCKET_NAME"
$AWS s3 mb "s3://$BUCKET_NAME" --region "$REGION"

# Create SQS queue
echo "Creating SQS queue: $QUEUE_NAME"
QUEUE_URL=$($AWS sqs create-queue \
    --queue-name "$QUEUE_NAME" \
    --query 'QueueUrl' \
    --output text \
    --region "$REGION")
echo "QUEUE_URL=$QUEUE_URL" >> "$SCRIPT_DIR/.env"

# Package Lambda functions
echo "Packaging Lambda functions..."
PACKAGE_DIR=$(mktemp -d)

# HTTP handler
cp "$SRC_DIR/http_handler.py" "$PACKAGE_DIR/handler.py"
cd "$PACKAGE_DIR" && zip -r http.zip handler.py && cd - > /dev/null

# S3 handler
cp "$SRC_DIR/s3_handler.py" "$PACKAGE_DIR/handler.py"
cd "$PACKAGE_DIR" && zip -r s3.zip handler.py && cd - > /dev/null

# SQS handler
cp "$SRC_DIR/sqs_handler.py" "$PACKAGE_DIR/handler.py"
cd "$PACKAGE_DIR" && zip -r sqs.zip handler.py && cd - > /dev/null

# Create Lambda functions
echo "Creating Lambda function: $HTTP_FUNCTION"
$AWS lambda create-function \
    --function-name "$HTTP_FUNCTION" \
    --runtime python3.12 \
    --handler handler.handler \
    --role "$ROLE_ARN" \
    --zip-file "fileb://$PACKAGE_DIR/http.zip" \
    --environment "Variables={TABLE_NAME=$TABLE_NAME,QUEUE_URL=$QUEUE_URL}" \
    --region "$REGION"

echo "Creating Lambda function: $S3_FUNCTION"
$AWS lambda create-function \
    --function-name "$S3_FUNCTION" \
    --runtime python3.12 \
    --handler handler.handler \
    --role "$ROLE_ARN" \
    --zip-file "fileb://$PACKAGE_DIR/s3.zip" \
    --environment "Variables={TABLE_NAME=$TABLE_NAME}" \
    --region "$REGION"

echo "Creating Lambda function: $SQS_FUNCTION"
$AWS lambda create-function \
    --function-name "$SQS_FUNCTION" \
    --runtime python3.12 \
    --handler handler.handler \
    --role "$ROLE_ARN" \
    --zip-file "fileb://$PACKAGE_DIR/sqs.zip" \
    --environment "Variables={TABLE_NAME=$TABLE_NAME}" \
    --region "$REGION"

# Wait for all Lambda functions to be active
echo "Waiting for Lambda functions to be active..."
for func_name in "$HTTP_FUNCTION" "$S3_FUNCTION" "$SQS_FUNCTION"; do
    for i in {1..30}; do
        STATE=$($AWS lambda get-function --function-name "$func_name" --query 'Configuration.State' --output text --region "$REGION" 2>/dev/null || echo "Pending")
        if [[ "$STATE" == "Active" ]]; then
            echo "  $func_name is active"
            break
        fi
        sleep 2
    done
done

# Get Lambda ARNs
HTTP_ARN=$($AWS lambda get-function --function-name "$HTTP_FUNCTION" --query 'Configuration.FunctionArn' --output text --region "$REGION")
S3_ARN=$($AWS lambda get-function --function-name "$S3_FUNCTION" --query 'Configuration.FunctionArn' --output text --region "$REGION")
SQS_ARN=$($AWS lambda get-function --function-name "$SQS_FUNCTION" --query 'Configuration.FunctionArn' --output text --region "$REGION")

echo "HTTP_ARN=$HTTP_ARN" >> "$SCRIPT_DIR/.env"
echo "S3_ARN=$S3_ARN" >> "$SCRIPT_DIR/.env"
echo "SQS_ARN=$SQS_ARN" >> "$SCRIPT_DIR/.env"

# Create Function URL for HTTP handler
echo "Creating Function URL..."
FUNCTION_URL=$($AWS lambda create-function-url-config \
    --function-name "$HTTP_FUNCTION" \
    --auth-type NONE \
    --query 'FunctionUrl' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$FUNCTION_URL" ]]; then
    echo "FUNCTION_URL=$FUNCTION_URL" >> "$SCRIPT_DIR/.env"
fi

# Add S3 trigger
echo "Configuring S3 trigger..."
$AWS lambda add-permission \
    --function-name "$S3_FUNCTION" \
    --statement-id s3-invoke \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn "arn:aws:s3:::$BUCKET_NAME" \
    --region "$REGION" > /dev/null 2>&1 || true

NOTIFICATION_CONFIG=$(cat << EOF
{
    "LambdaFunctionConfigurations": [{
        "LambdaFunctionArn": "$S3_ARN",
        "Events": ["s3:ObjectCreated:*"]
    }]
}
EOF
)

$AWS s3api put-bucket-notification-configuration \
    --bucket "$BUCKET_NAME" \
    --notification-configuration "$NOTIFICATION_CONFIG" \
    --region "$REGION"

# Add SQS trigger
echo "Configuring SQS trigger..."
QUEUE_ARN="arn:aws:sqs:$REGION:$ACCOUNT_ID:$QUEUE_NAME"

$AWS lambda create-event-source-mapping \
    --function-name "$SQS_FUNCTION" \
    --event-source-arn "$QUEUE_ARN" \
    --batch-size 10 \
    --region "$REGION" > /dev/null 2>&1 || true

# Cleanup
rm -rf "$PACKAGE_DIR"

echo ""
echo "Deployment complete!"
echo "  DynamoDB Table: $TABLE_NAME"
echo "  S3 Bucket: $BUCKET_NAME"
echo "  SQS Queue: $QUEUE_NAME"
echo "  HTTP Function: $HTTP_FUNCTION"
echo "  S3 Function: $S3_FUNCTION"
echo "  SQS Function: $SQS_FUNCTION"
[[ -n "${FUNCTION_URL:-}" ]] && echo "  Function URL: $FUNCTION_URL"
