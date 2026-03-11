#!/bin/bash
set -euo pipefail

# Neptune Graph Database Terraform deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"

echo "Deploying Neptune Graph Database with Terraform..."

cd "$SCRIPT_DIR"

SUFFIX="${SUFFIX:-$(date +%s)}"

# Initialize Terraform
tflocal init -input=false

# Apply configuration
tflocal apply -auto-approve -var="cluster_id=neptune-test-cluster-${SUFFIX}"

# Extract cluster ID from terraform, then get actual details from Neptune API
# (Terraform returns default port 8182, but LocalStack assigns dynamic ports)
CLUSTER_ID=$(tflocal output -raw cluster_id)

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
