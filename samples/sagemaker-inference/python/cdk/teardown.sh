#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

echo "=== Tearing down SageMaker Inference (CDK) ==="

cd "$SCRIPT_DIR"

# Delete SageMaker resources before CDK destroy
$AWSCLI sagemaker delete-endpoint --endpoint-name sample-ep-cdk 2>/dev/null || true
$AWSCLI sagemaker delete-endpoint-config --endpoint-config-name sample-cf-cdk 2>/dev/null || true
$AWSCLI sagemaker delete-model --model-name sample-cdk 2>/dev/null || true

$CDK destroy --force 2>/dev/null || true

rm -f cdk-outputs.json
rm -rf cdk.out
rm -f ../scripts/.env

echo "Teardown complete!"
