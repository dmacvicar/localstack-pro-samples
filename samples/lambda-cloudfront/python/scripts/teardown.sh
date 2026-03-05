#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Tearing down Lambda CloudFront Sample (scripts)"

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

# Read .env to get resource names
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    source "$SCRIPT_DIR/.env"
fi

FUNCTION_NAME="${FUNCTION_NAME:-}"
ROLE_NAME="${ROLE_NAME:-}"

# Delete Lambda function URL config
if [[ -n "$FUNCTION_NAME" ]]; then
    echo "Deleting Lambda function URL config..."
    $AWS lambda delete-function-url-config --function-name "$FUNCTION_NAME" --region "$REGION" 2>/dev/null || true

    echo "Deleting Lambda function..."
    $AWS lambda delete-function --function-name "$FUNCTION_NAME" --region "$REGION" 2>/dev/null || true
fi

# Delete IAM role (extract from ROLE_ARN if set)
if [[ -n "${ROLE_ARN:-}" ]]; then
    ROLE_NAME=$(echo "$ROLE_ARN" | sed 's/.*role\///')
fi

if [[ -n "$ROLE_NAME" ]]; then
    echo "Deleting IAM role..."
    $AWS iam delete-role --role-name "$ROLE_NAME" --region "$REGION" 2>/dev/null || true
fi

# Clean up .env
rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete!"
