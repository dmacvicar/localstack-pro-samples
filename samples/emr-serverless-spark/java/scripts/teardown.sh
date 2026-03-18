#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

echo "=== Tearing down EMR Serverless Spark (Scripts) ==="

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

if [ -n "${APP_ID:-}" ]; then
    $AWSCLI emr-serverless stop-application --application-id "$APP_ID" 2>/dev/null || true
    sleep 2
    $AWSCLI emr-serverless delete-application --application-id "$APP_ID" 2>/dev/null || true
fi

$AWSCLI iam delete-role --role-name emr-serverless-role-scripts 2>/dev/null || true
$AWSCLI s3 rb "s3://emr-spark-scripts" --force 2>/dev/null || true

rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete!"
