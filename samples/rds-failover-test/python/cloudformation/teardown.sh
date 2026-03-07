#!/bin/bash
set -euo pipefail

# RDS Failover Test CloudFormation teardown script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="rds-failover-test"

echo "Tearing down RDS Failover Test CloudFormation resources..."

# Delete secondary cluster if env file exists
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    if [ -n "${SECONDARY_CLUSTER_ID:-}" ]; then
        awslocal rds delete-db-cluster \
            --db-cluster-identifier "$SECONDARY_CLUSTER_ID" \
            --skip-final-snapshot \
            --region us-west-1 2>/dev/null || true
    fi
fi

# Delete stack
awslocal cloudformation delete-stack --stack-name "$STACK_NAME" 2>/dev/null || true

# Wait for deletion
awslocal cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" 2>/dev/null || true

# Clean up
rm -f "$ENV_FILE"

echo "Teardown complete"
