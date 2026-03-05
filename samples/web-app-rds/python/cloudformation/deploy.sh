#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="web-app-rds-stack"
FUNCTION_NAME="webapp-rds-cfn"
DB_INSTANCE_ID="webapp-postgres-cfn"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Web App RDS Sample via CloudFormation"
echo "  Stack: $STACK_NAME"
echo "  Region: $REGION"

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

cd "$SCRIPT_DIR"

# Deploy CloudFormation stack
echo ""
echo "Step 1: Deploying CloudFormation stack..."
$AWS cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file template.yml \
    --parameter-overrides \
        "FunctionName=$FUNCTION_NAME" \
        "DBInstanceId=$DB_INSTANCE_ID" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --no-fail-on-empty-changeset

# Wait for stack to complete
echo "Step 2: Waiting for stack to complete..."
$AWS cloudformation wait stack-create-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION" 2>/dev/null || \
$AWS cloudformation wait stack-update-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION" 2>/dev/null || true

# Wait for RDS to be available
echo "Step 3: Waiting for RDS instance..."
MAX_ATTEMPTS=30
ATTEMPT=1

while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
    STATUS=$($AWS rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "pending")

    if [[ "$STATUS" == "available" ]]; then
        echo "  RDS instance is available"
        break
    fi
    echo "  Status: $STATUS (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done

# Extract outputs
echo "Step 4: Extracting outputs..."
STACK_OUTPUTS=$($AWS cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs' \
    --region "$REGION" 2>/dev/null)

FUNCTION_NAME=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionName") | .OutputValue')
FUNCTION_URL=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionUrl") | .OutputValue')
LAMBDA_ARN=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionArn") | .OutputValue')
DB_HOST=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="DBHost") | .OutputValue')
DB_PORT=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="DBPort") | .OutputValue')

# Save config for test script (shared with scripts/)
cat > "$SCRIPT_DIR/../scripts/.env" << EOF
FUNCTION_NAME=$FUNCTION_NAME
FUNCTION_URL=$FUNCTION_URL
LAMBDA_ARN=$LAMBDA_ARN
DB_INSTANCE_ID=$DB_INSTANCE_ID
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=appdb
DB_USER=admin
REGION=$REGION
STACK_NAME=$STACK_NAME
EOF

echo ""
echo "Deployment complete!"
echo "  Function Name: $FUNCTION_NAME"
echo "  Function URL: $FUNCTION_URL"
echo "  RDS Instance: $DB_INSTANCE_ID"
echo ""
echo "Run tests with: ../scripts/test.sh"
