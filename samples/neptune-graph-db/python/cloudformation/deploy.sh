#!/bin/bash
set -euo pipefail

# Neptune Graph Database CloudFormation deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="neptune-graph-db"

SUFFIX="${SUFFIX:-$(date +%s)}"
CLUSTER_ID="neptune-test-cluster-${SUFFIX}"

echo "Deploying Neptune Graph Database with CloudFormation..."

cd "$SCRIPT_DIR"

# Deploy CloudFormation stack
awslocal cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file template.yml \
    --parameter-overrides \
        ClusterId="$CLUSTER_ID" \
    --no-fail-on-empty-changeset

# Extract outputs
CLUSTER_ID=$(awslocal cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ClusterId'].OutputValue" \
    --output text)

# Get cluster details from Neptune API (ARN not available via GetAtt,
# and port/endpoint are more reliable from the API)
CLUSTER_INFO=$(awslocal neptune describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --output json)

CLUSTER_ARN=$(echo "$CLUSTER_INFO" | jq -r '.DBClusters[0].DBClusterArn')
CLUSTER_ENDPOINT=$(echo "$CLUSTER_INFO" | jq -r '.DBClusters[0].Endpoint // empty')
CLUSTER_PORT=$(echo "$CLUSTER_INFO" | jq -r '.DBClusters[0].Port // empty')

echo ""
echo "Neptune cluster deployed successfully!"
echo "  Stack: $STACK_NAME"
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
