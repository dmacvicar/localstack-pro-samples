#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="lambda-layers-cfn-stack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Tearing down Lambda Layers Sample (cloudformation)"

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

S3_BUCKET="lambda-layers-cfn-deployment"

# Delete CloudFormation stack
echo "Deleting CloudFormation stack..."
$AWS cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
$AWS cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true

# Delete S3 bucket
echo "Deleting S3 bucket..."
$AWS s3 rb "s3://$S3_BUCKET" --force --region "$REGION" 2>/dev/null || true

# Clean up local files
rm -f "$SCRIPT_DIR/layer.zip" "$SCRIPT_DIR/function.zip"

# Clean up .env
rm -f "$PROJECT_DIR/scripts/.env"

echo "Teardown complete!"
