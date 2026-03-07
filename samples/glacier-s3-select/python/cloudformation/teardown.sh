#!/bin/bash
set -euo pipefail

# Glacier S3 Select CloudFormation teardown script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="glacier-s3-select"

echo "Tearing down Glacier S3 Select CloudFormation resources..."

# Delete stack
awslocal cloudformation delete-stack --stack-name "$STACK_NAME" 2>/dev/null || true

# Wait for deletion
awslocal cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" 2>/dev/null || true

# Clean up
rm -f "$ENV_FILE"

echo "Teardown complete"
