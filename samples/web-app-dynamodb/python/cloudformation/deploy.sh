#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="web-app-dynamodb-stack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Web App DynamoDB via CloudFormation"

# Use aws CLI directly with endpoint-url to avoid awslocal --s3-endpoint-url bug
AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

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

FUNCTION_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionName") | .OutputValue')
FUNCTION_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionUrl") | .OutputValue')
TABLE_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="TableName") | .OutputValue')

cat > "$SCRIPT_DIR/../scripts/.env" << EOF
FUNCTION_NAME=$FUNCTION_NAME
FUNCTION_URL=$FUNCTION_URL
TABLE_NAME=$TABLE_NAME
REGION=$REGION
EOF

echo ""
echo "Deployment complete!"
echo "  Function: $FUNCTION_NAME"
echo "  Table: $TABLE_NAME"
echo "  URL: $FUNCTION_URL"
