#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Tearing down Lambda Container Image Sample (scripts)"

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

FUNCTION_NAME="lambda-container-sample"
REPO_NAME="lambda-container-sample"

# Delete Lambda function
echo "Deleting Lambda function..."
$AWS lambda delete-function --function-name "$FUNCTION_NAME" --region "$REGION" 2>/dev/null || true

# Delete ECR repository (force delete images)
echo "Deleting ECR repository..."
$AWS ecr delete-repository --repository-name "$REPO_NAME" --force --region "$REGION" 2>/dev/null || true

# Clean up .env
rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete!"
