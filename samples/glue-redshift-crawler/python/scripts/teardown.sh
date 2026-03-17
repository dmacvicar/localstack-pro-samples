#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

echo "=== Tearing down Glue Redshift Crawler ==="

[ -n "${GLUE_CRAWLER_NAME:-}" ] && $AWSCLI glue delete-crawler --name "$GLUE_CRAWLER_NAME" 2>/dev/null || true
[ -n "${GLUE_CONNECTION_NAME:-}" ] && $AWSCLI glue delete-connection --connection-name "$GLUE_CONNECTION_NAME" 2>/dev/null || true
[ -n "${GLUE_DB_NAME:-}" ] && $AWSCLI glue delete-database --name "$GLUE_DB_NAME" 2>/dev/null || true
[ -n "${REDSHIFT_CLUSTER_ID:-}" ] && $AWSCLI redshift delete-cluster --cluster-identifier "$REDSHIFT_CLUSTER_ID" --skip-final-cluster-snapshot 2>/dev/null || true

rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete!"
