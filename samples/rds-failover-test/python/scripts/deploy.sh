#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUFFIX="${SUFFIX:-$(date +%s)}"
GLOBAL_CLUSTER_ID="global-cluster-${SUFFIX}"
PRIMARY_CLUSTER_ID="rds-cluster-1-${SUFFIX}"
SECONDARY_CLUSTER_ID="rds-cluster-2-${SUFFIX}"

LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"

echo "Creating global Aurora PostgreSQL cluster..."
awslocal rds create-global-cluster \
    --global-cluster-identifier "$GLOBAL_CLUSTER_ID" \
    --engine aurora-postgresql \
    --engine-version 13.7 \
    --endpoint-url "$LOCALSTACK_ENDPOINT" > /dev/null

echo "Creating primary DB cluster in us-east-1..."
PRIMARY_ARN=$(awslocal rds create-db-cluster \
    --db-cluster-identifier "$PRIMARY_CLUSTER_ID" \
    --engine aurora-postgresql \
    --engine-version 13.7 \
    --database-name test \
    --global-cluster-identifier "$GLOBAL_CLUSTER_ID" \
    --region us-east-1 \
    --query 'DBCluster.DBClusterArn' \
    --output text \
    --endpoint-url "$LOCALSTACK_ENDPOINT")

echo "Adding instance to primary cluster..."
awslocal rds create-db-instance \
    --db-cluster-identifier "$PRIMARY_CLUSTER_ID" \
    --db-instance-identifier "inst-1-${SUFFIX}" \
    --engine aurora-postgresql \
    --engine-version 13.7 \
    --db-instance-class db.r5.large \
    --region us-east-1 \
    --endpoint-url "$LOCALSTACK_ENDPOINT" > /dev/null

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

# Save configuration for tests
cat > "$SCRIPT_DIR/.env" << EOF
GLOBAL_CLUSTER_ID=$GLOBAL_CLUSTER_ID
PRIMARY_CLUSTER_ID=$PRIMARY_CLUSTER_ID
SECONDARY_CLUSTER_ID=$SECONDARY_CLUSTER_ID
PRIMARY_ARN=$PRIMARY_ARN
SECONDARY_ARN=$SECONDARY_ARN
EOF

echo ""
echo "Deployment complete!"
echo "Global Cluster: $GLOBAL_CLUSTER_ID"
echo "Primary Cluster: $PRIMARY_CLUSTER_ID"
echo "Secondary Cluster: $SECONDARY_CLUSTER_ID"
