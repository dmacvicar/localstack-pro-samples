#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="WebAppRdsStack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Web App RDS Sample via CDK"
echo "  Stack: $STACK_NAME"
echo "  Region: $REGION"

cd "$SCRIPT_DIR"

# Determine CDK CLI to use
if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    echo "Warning: cdklocal not found, using cdk (may not work with LocalStack)"
    CDK="cdk"
fi

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

# Install Python dependencies
echo ""
echo "Step 1: Installing CDK dependencies..."
uv pip install --system -r requirements.txt --quiet 2>/dev/null || true

# Bootstrap CDK (if needed)
echo "Step 2: Bootstrapping CDK..."
$CDK bootstrap --quiet 2>/dev/null || true

# Deploy stack
echo "Step 3: Deploying CDK stack..."
$CDK deploy --require-approval never --outputs-file cdk-outputs.json

# Wait for RDS to be available
echo "Step 4: Waiting for RDS instance..."
DB_INSTANCE_ID=$(jq -r ".$STACK_NAME.DBInstanceId" cdk-outputs.json)
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
echo "Step 5: Extracting outputs..."
FUNCTION_NAME=$(jq -r ".$STACK_NAME.FunctionName" cdk-outputs.json)
FUNCTION_URL=$(jq -r ".$STACK_NAME.FunctionUrl" cdk-outputs.json)
LAMBDA_ARN=$(jq -r ".$STACK_NAME.FunctionArn" cdk-outputs.json)
DB_HOST=$(jq -r ".$STACK_NAME.DBHost" cdk-outputs.json)
DB_PORT=$(jq -r ".$STACK_NAME.DBPort" cdk-outputs.json)

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
