#!/bin/bash
set -euo pipefail

# RDS Failover Test CDK teardown script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="RdsFailoverTestStack"

echo "Tearing down RDS Failover Test CDK resources..."

cd "$SCRIPT_DIR"

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

# Destroy stack
cdklocal destroy "$STACK_NAME" --force 2>/dev/null || true

# Clean up
rm -f "$ENV_FILE"
rm -f outputs.json
rm -rf cdk.out

echo "Teardown complete"
