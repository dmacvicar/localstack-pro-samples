#!/bin/bash
set -euo pipefail

# IAM Policy Enforcement CloudFormation teardown script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="iam-policy-enforcement"

echo "Tearing down IAM policy enforcement CloudFormation resources..."

# Delete stack
awslocal cloudformation delete-stack --stack-name "$STACK_NAME" 2>/dev/null || true

# Wait for deletion
echo "Waiting for stack deletion..."
awslocal cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" 2>/dev/null || true

# Clean up
rm -f "$ENV_FILE"

echo "Teardown complete"
