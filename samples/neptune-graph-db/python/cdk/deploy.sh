#!/bin/bash
set -euo pipefail

# Neptune Graph Database CDK deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="NeptuneGraphDbStack"

SUFFIX="${SUFFIX:-$(date +%s)}"
export CLUSTER_ID="neptune-test-cluster-${SUFFIX}"

echo "Deploying Neptune Graph Database with CDK..."

cd "$SCRIPT_DIR"

# Install CDK dependencies
pip install -q -r requirements.txt

# Bootstrap CDK (if needed)
cdklocal bootstrap --quiet 2>/dev/null || true

# Deploy
cdklocal deploy "$STACK_NAME" --require-approval never --outputs-file outputs.json

# Extract cluster ID from CDK outputs, then get details from Neptune API
# (ARN not available via CDK, and port/endpoint more reliable from API)
CLUSTER_ID=$(jq -r ".\"$STACK_NAME\".ClusterId" outputs.json)

CLUSTER_INFO=$(awslocal neptune describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --output json)

CLUSTER_ARN=$(echo "$CLUSTER_INFO" | jq -r '.DBClusters[0].DBClusterArn')
CLUSTER_ENDPOINT=$(echo "$CLUSTER_INFO" | jq -r '.DBClusters[0].Endpoint // empty')
CLUSTER_PORT=$(echo "$CLUSTER_INFO" | jq -r '.DBClusters[0].Port // empty')

echo ""
echo "Neptune cluster deployed successfully!"
echo "  Cluster ID: $CLUSTER_ID"
echo "  Cluster ARN: $CLUSTER_ARN"
echo "  Endpoint: $CLUSTER_ENDPOINT"
echo "  Port: $CLUSTER_PORT"

# Write environment variables
mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" << EOF
CLUSTER_ID=$CLUSTER_ID
CLUSTER_ARN=$CLUSTER_ARN
CLUSTER_ENDPOINT=$CLUSTER_ENDPOINT
CLUSTER_PORT=$CLUSTER_PORT
EOF

echo ""
echo "Environment written to $ENV_FILE"
