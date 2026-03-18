#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

echo "=== Tearing down SageMaker Inference (Scripts) ==="

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

$AWSCLI sagemaker delete-endpoint --endpoint-name "${ENDPOINT_NAME:-sample-ep-scripts}" 2>/dev/null || true
$AWSCLI sagemaker delete-endpoint-config --endpoint-config-name "${CONFIG_NAME:-sample-cf-scripts}" 2>/dev/null || true
$AWSCLI sagemaker delete-model --model-name "${MODEL_NAME:-sample-scripts}" 2>/dev/null || true
$AWSCLI s3 rb "s3://sagemaker-models-scripts" --force 2>/dev/null || true

rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete!"
