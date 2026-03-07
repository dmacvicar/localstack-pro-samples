#!/bin/bash
set -euo pipefail

# RDS Failover Test CloudFormation deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="rds-failover-test"
LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"

SUFFIX="${SUFFIX:-$(date +%s)}"
GLOBAL_CLUSTER_ID="global-cluster-${SUFFIX}"
PRIMARY_CLUSTER_ID="rds-cluster-1-${SUFFIX}"
SECONDARY_CLUSTER_ID="rds-cluster-2-${SUFFIX}"

echo "Deploying RDS Failover Test with CloudFormation..."

cd "$SCRIPT_DIR"

# Deploy CloudFormation stack (primary region)
awslocal cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file template.yml \
    --parameter-overrides \
        GlobalClusterId="$GLOBAL_CLUSTER_ID" \
        PrimaryClusterId="$PRIMARY_CLUSTER_ID" \
    --no-fail-on-empty-changeset

# Get primary cluster ARN
PRIMARY_ARN=$(awslocal cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='PrimaryArn'].OutputValue" \
    --output text)

# Create secondary cluster in us-west-1 (CloudFormation can't do cross-region)
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
echo "  Stack: $STACK_NAME"
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
