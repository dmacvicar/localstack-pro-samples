#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

STACK_NAME="sagemaker-inference"

echo "=== Tearing down SageMaker Inference (CloudFormation) ==="

$AWSCLI sagemaker delete-endpoint --endpoint-name sample-ep-cfn 2>/dev/null || true
$AWSCLI sagemaker delete-endpoint-config --endpoint-config-name sample-cf-cfn 2>/dev/null || true
$AWSCLI sagemaker delete-model --model-name sample-cfn 2>/dev/null || true
$AWSCLI s3 rb "s3://sagemaker-models-cfn" --force 2>/dev/null || true
$AWSCLI cloudformation delete-stack --stack-name "$STACK_NAME" 2>/dev/null || true

rm -f "$SCRIPT_DIR/../scripts/.env"

echo "Teardown complete!"
