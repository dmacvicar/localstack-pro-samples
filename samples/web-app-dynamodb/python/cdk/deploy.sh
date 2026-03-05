#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="WebAppDynamoDBStack"

echo "Deploying Web App DynamoDB via CDK"

cd "$SCRIPT_DIR"

if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

if command -v awslocal &> /dev/null; then
    AWS="awslocal"
else
    AWS="aws --endpoint-url=http://localhost:4566"
fi

echo "Step 1: Installing CDK dependencies..."
uv pip install --system -r requirements.txt --quiet 2>/dev/null || true

echo "Step 2: Bootstrapping CDK..."
$CDK bootstrap --quiet 2>/dev/null || true

echo "Step 3: Deploying CDK stack..."
$CDK deploy --require-approval never --outputs-file cdk-outputs.json

echo "Step 4: Extracting outputs..."
FUNCTION_NAME=$(jq -r ".$STACK_NAME.FunctionName" cdk-outputs.json)
FUNCTION_URL=$(jq -r ".$STACK_NAME.FunctionUrl" cdk-outputs.json)
TABLE_NAME=$(jq -r ".$STACK_NAME.TableName" cdk-outputs.json)

cat > "$SCRIPT_DIR/../scripts/.env" << EOF
FUNCTION_NAME=$FUNCTION_NAME
FUNCTION_URL=$FUNCTION_URL
TABLE_NAME=$TABLE_NAME
REGION=us-east-1
EOF

echo ""
echo "Deployment complete!"
echo "  Function: $FUNCTION_NAME"
echo "  Table: $TABLE_NAME"
echo "  URL: $FUNCTION_URL"
