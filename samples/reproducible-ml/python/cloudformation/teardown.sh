#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

STACK_NAME="reproducible-ml"

echo "=== Tearing down Reproducible ML (CloudFormation) ==="

$AWSCLI s3 rb "s3://reproducible-ml-cfn" --force 2>/dev/null || true
$AWSCLI cloudformation delete-stack --stack-name "$STACK_NAME" 2>/dev/null || true

rm -f "$SCRIPT_DIR/../scripts/.env"

echo "Teardown complete!"
