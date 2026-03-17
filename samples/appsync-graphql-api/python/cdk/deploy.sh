#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use cdklocal if available, otherwise cdk
if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

echo "=== Deploying AppSync GraphQL API (CDK) ==="

cd "$SCRIPT_DIR"

# Install dependencies
uv pip install --system -r requirements.txt 2>/dev/null || pip install -r requirements.txt

# Bootstrap CDK
$CDK bootstrap 2>/dev/null || true

# Deploy
$CDK deploy --require-approval never --outputs-file cdk-outputs.json

# Extract outputs
STACK_OUTPUT=$(cat cdk-outputs.json | jq -r '.AppSyncGraphQLApiStack')

# Save to shared .env
cat > "$SCRIPT_DIR/../scripts/.env" << EOF
API_ID=$(echo "$STACK_OUTPUT" | jq -r '.ApiId')
API_URL=$(echo "$STACK_OUTPUT" | jq -r '.ApiUrl')
API_KEY=$(echo "$STACK_OUTPUT" | jq -r '.ApiKeyValue')
API_NAME=$(echo "$STACK_OUTPUT" | jq -r '.ApiName')
TABLE_NAME=$(echo "$STACK_OUTPUT" | jq -r '.TableName')
DB_CLUSTER_ID=$(echo "$STACK_OUTPUT" | jq -r '.DBClusterId')
DB_CLUSTER_ARN=$(echo "$STACK_OUTPUT" | jq -r '.DBClusterArn')
DB_NAME=$(echo "$STACK_OUTPUT" | jq -r '.DBName')
SECRET_ARN=$(echo "$STACK_OUTPUT" | jq -r '.SecretArn')
ROLE_ARN=$(echo "$STACK_OUTPUT" | jq -r '.RoleArn')
EOF

echo ""
echo "Deployment complete!"
echo "API ID: $(echo "$STACK_OUTPUT" | jq -r '.ApiId')"
echo "API URL: $(echo "$STACK_OUTPUT" | jq -r '.ApiUrl')"
