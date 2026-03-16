#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use awslocal if available, otherwise aws with endpoint
if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

STACK_NAME="route53-dns-failover"

echo "=== Tearing down Route53 DNS Failover (CloudFormation) ==="

$AWSCLI cloudformation delete-stack --stack-name "$STACK_NAME" 2>/dev/null || true
$AWSCLI cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" 2>/dev/null || true

rm -f ../scripts/.env

echo "Teardown complete!"
