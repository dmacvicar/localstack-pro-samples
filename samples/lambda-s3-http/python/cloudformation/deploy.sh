#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="lambda-s3-http-stack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Lambda S3 HTTP via CloudFormation"

# Use aws CLI directly with endpoint-url to avoid awslocal --s3-endpoint-url bug
AWS="aws --endpoint-url=http://localhost:4566"

cd "$SCRIPT_DIR"

echo "Step 1: Deploying CloudFormation stack..."
$AWS cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file template.yml \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --no-fail-on-empty-changeset

echo "Step 2: Extracting outputs..."
OUTPUTS=$($AWS cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs' --region "$REGION")

TABLE_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="TableName") | .OutputValue')
BUCKET_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="BucketName") | .OutputValue')
QUEUE_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="QueueName") | .OutputValue')
QUEUE_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="QueueUrl") | .OutputValue')
HTTP_FUNCTION=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="HttpFunction") | .OutputValue')
S3_FUNCTION=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="S3Function") | .OutputValue')
S3_FUNCTION_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="S3FunctionArn") | .OutputValue')
SQS_FUNCTION=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="SqsFunction") | .OutputValue')

echo "Step 3: Configuring S3 notification..."
NOTIFICATION_CONFIG=$(cat << EOF
{
    "LambdaFunctionConfigurations": [{
        "LambdaFunctionArn": "$S3_FUNCTION_ARN",
        "Events": ["s3:ObjectCreated:*"]
    }]
}
EOF
)

$AWS s3api put-bucket-notification-configuration \
    --bucket "$BUCKET_NAME" \
    --notification-configuration "$NOTIFICATION_CONFIG" \
    --region "$REGION"

cat > "$SCRIPT_DIR/../scripts/.env" << EOF
TABLE_NAME=$TABLE_NAME
BUCKET_NAME=$BUCKET_NAME
QUEUE_NAME=$QUEUE_NAME
QUEUE_URL=$QUEUE_URL
HTTP_FUNCTION=$HTTP_FUNCTION
S3_FUNCTION=$S3_FUNCTION
SQS_FUNCTION=$SQS_FUNCTION
REGION=$REGION
EOF

echo ""
echo "Deployment complete!"
echo "  Table: $TABLE_NAME"
echo "  Bucket: $BUCKET_NAME"
echo "  Queue: $QUEUE_NAME"
echo "  HTTP Function: $HTTP_FUNCTION"
echo "  S3 Function: $S3_FUNCTION"
echo "  SQS Function: $SQS_FUNCTION"
