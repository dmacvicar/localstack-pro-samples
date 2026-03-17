#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use awslocal if available, otherwise aws with endpoint
if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

echo "=== Tearing down Glue MSK Schema Registry ==="

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"

    # Delete schema
    if [ -n "${SCHEMA_ARN:-}" ]; then
        $AWSCLI glue delete-schema --schema-id "SchemaArn=${SCHEMA_ARN}" 2>/dev/null || true
    fi

    # Delete registry
    if [ -n "${REGISTRY_NAME:-}" ]; then
        $AWSCLI glue delete-registry --registry-id "RegistryName=${REGISTRY_NAME}" 2>/dev/null || true
    fi

    # Delete MSK cluster
    if [ -n "${CLUSTER_ARN:-}" ]; then
        $AWSCLI kafka delete-cluster --cluster-arn "$CLUSTER_ARN" 2>/dev/null || true
    fi

    rm -f "$SCRIPT_DIR/.env"
fi

echo "Teardown complete!"
