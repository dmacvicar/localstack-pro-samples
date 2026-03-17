#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use awslocal if available, otherwise aws with endpoint
if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

STACK_NAME="appsync-graphql-api"

echo "=== Deploying AppSync GraphQL API (CloudFormation) ==="

# Deploy the stack
$AWSCLI cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file "$SCRIPT_DIR/template.yml" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset 2>/dev/null || \
$AWSCLI cloudformation create-stack \
    --stack-name "$STACK_NAME" \
    --template-body "file://$SCRIPT_DIR/template.yml" \
    --capabilities CAPABILITY_NAMED_IAM

# Wait for stack
echo "Waiting for stack to complete..."
$AWSCLI cloudformation wait stack-create-complete --stack-name "$STACK_NAME" 2>/dev/null || \
$AWSCLI cloudformation wait stack-update-complete --stack-name "$STACK_NAME" 2>/dev/null || true

# Extract outputs
OUTPUTS=$($AWSCLI cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs')

get_output() {
    echo "$OUTPUTS" | jq -r ".[] | select(.OutputKey==\"$1\") | .OutputValue"
}

# Save to shared .env
cat > "$SCRIPT_DIR/../scripts/.env" << EOF
API_ID=$(get_output "ApiId")
API_URL=$(get_output "ApiUrl")
API_KEY=$(get_output "ApiKey")
API_NAME=$(get_output "ApiName")
TABLE_NAME=$(get_output "TableName")
DB_CLUSTER_ID=$(get_output "DBClusterId")
DB_CLUSTER_ARN=$(get_output "DBClusterArn")
DB_NAME=$(get_output "DBName")
SECRET_ARN=$(get_output "SecretArn")
ROLE_ARN=$(get_output "RoleArn")
STACK_NAME=$STACK_NAME
EOF

echo ""
echo "Deployment complete!"
echo "API ID: $(get_output "ApiId")"
echo "API URL: $(get_output "ApiUrl")"
