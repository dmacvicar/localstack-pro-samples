#!/bin/bash
set -euo pipefail

# RDS Failover Test CDK deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="RdsFailoverTestStack"
LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"

SUFFIX="${SUFFIX:-$(date +%s)}"
export GLOBAL_CLUSTER_ID="global-cluster-${SUFFIX}"
export PRIMARY_CLUSTER_ID="rds-cluster-1-${SUFFIX}"
SECONDARY_CLUSTER_ID="rds-cluster-2-${SUFFIX}"

echo "Deploying RDS Failover Test with CDK..."

cd "$SCRIPT_DIR"

# Install CDK dependencies
pip install -q -r requirements.txt

# Bootstrap CDK (if needed)
cdklocal bootstrap --quiet 2>/dev/null || true

# Deploy
cdklocal deploy "$STACK_NAME" --require-approval never --outputs-file outputs.json

# Extract outputs
PRIMARY_ARN=$(jq -r ".\"$STACK_NAME\".PrimaryArn" outputs.json)

# Create secondary cluster in us-west-1 (CDK can't do cross-region)
echo "Creating secondary DB cluster in us-west-1..."
SECONDARY_ARN=$(awslocal rds create-db-cluster \
    --db-cluster-identifier "$SECONDARY_CLUSTER_ID" \
    --engine aurora-postgresql \
    --engine-version 13.7 \
    --global-cluster-identifier "$GLOBAL_CLUSTER_ID" \
    --region us-west-1 \
    --query 'DBCluster.DBClusterArn' \
    --output text \
    --endpoint-url "$LOCALSTACK_ENDPOINT")

echo "Adding instance to secondary cluster..."
awslocal rds create-db-instance \
    --db-cluster-identifier "$SECONDARY_CLUSTER_ID" \
    --db-instance-identifier "inst-2-${SUFFIX}" \
    --engine aurora-postgresql \
    --engine-version 13.7 \
    --db-instance-class db.r5.large \
    --region us-west-1 \
    --endpoint-url "$LOCALSTACK_ENDPOINT" > /dev/null

echo ""
echo "RDS Failover Test deployed successfully!"
echo "  Global Cluster: $GLOBAL_CLUSTER_ID"
echo "  Primary Cluster: $PRIMARY_CLUSTER_ID"
echo "  Secondary Cluster: $SECONDARY_CLUSTER_ID"

# Write environment variables
mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" << EOF
GLOBAL_CLUSTER_ID=$GLOBAL_CLUSTER_ID
PRIMARY_CLUSTER_ID=$PRIMARY_CLUSTER_ID
SECONDARY_CLUSTER_ID=$SECONDARY_CLUSTER_ID
PRIMARY_ARN=$PRIMARY_ARN
SECONDARY_ARN=$SECONDARY_ARN
EOF

echo ""
echo "Environment written to $ENV_FILE"
