#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$SAMPLE_DIR/scripts/.env" ]; then
    source "$SAMPLE_DIR/scripts/.env"
fi

STACK_NAME="${STACK_NAME:-glue-etl-jobs}"

# Check if stack exists
if ! awslocal cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
    echo "Stack $STACK_NAME does not exist. Nothing to tear down."
    rm -f "$SAMPLE_DIR/scripts/.env"
    exit 0
fi

# Empty S3 buckets first
for bucket in "${BUCKET:-}" "${TARGET_BUCKET:-}"; do
    if [ -n "$bucket" ]; then
        echo "Emptying S3 bucket: $bucket"
        awslocal s3 rm "s3://$bucket" --recursive || true
    fi
done

echo "Deleting CloudFormation stack: $STACK_NAME"
awslocal cloudformation delete-stack --stack-name "$STACK_NAME"

echo "Waiting for stack deletion..."
awslocal cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" || true

# Clean up .env file
rm -f "$SAMPLE_DIR/scripts/.env"

echo "Teardown complete!"
