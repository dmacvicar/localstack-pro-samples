#!/bin/bash
set -euo pipefail

# RDS Failover Test Terraform deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"

echo "Deploying RDS Failover Test with Terraform..."

cd "$SCRIPT_DIR"

# Initialize Terraform
tflocal init -input=false

# Apply configuration
tflocal apply -auto-approve

# Extract outputs
GLOBAL_CLUSTER_ID=$(tflocal output -raw global_cluster_id)
PRIMARY_CLUSTER_ID=$(tflocal output -raw primary_cluster_id)
SECONDARY_CLUSTER_ID=$(tflocal output -raw secondary_cluster_id)
PRIMARY_ARN=$(tflocal output -raw primary_arn)
SECONDARY_ARN=$(tflocal output -raw secondary_arn)

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
