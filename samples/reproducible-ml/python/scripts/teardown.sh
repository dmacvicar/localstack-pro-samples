#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

echo "=== Tearing down Reproducible ML (Scripts) ==="

$AWSCLI lambda delete-function --function-name ml-train-scripts 2>/dev/null || true
$AWSCLI lambda delete-function --function-name ml-predict-scripts 2>/dev/null || true
$AWSCLI s3 rb "s3://reproducible-ml-scripts" --force 2>/dev/null || true

rm -f "$SCRIPT_DIR/.env"
rm -f /tmp/ml-train.zip /tmp/ml-infer.zip /tmp/ml-train-result.json /tmp/ml-predict-result.json

echo "Teardown complete!"
