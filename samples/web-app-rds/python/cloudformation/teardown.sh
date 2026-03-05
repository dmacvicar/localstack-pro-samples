#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="web-app-rds-stack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Tearing down Web App RDS Sample (cloudformation)"

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

# Delete CloudFormation stack
echo "Deleting CloudFormation stack..."
$AWS cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
$AWS cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true

# Clean up .env
rm -f "$PROJECT_DIR/scripts/.env"

echo "Teardown complete!"
