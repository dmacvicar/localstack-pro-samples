#!/bin/bash
set -euo pipefail

# IAM Policy Enforcement teardown script
# Cleans up all IAM resources

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment if exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

USER_NAME="${USER_NAME:-iam-test-user}"
POLICY_NAME="${POLICY_NAME:-iam-test-policy}"
POLICY_ARN="${POLICY_ARN:-arn:aws:iam::000000000000:policy/$POLICY_NAME}"

echo "Tearing down IAM policy enforcement resources..."

# Detach policy from user
awslocal iam detach-user-policy \
    --user-name "$USER_NAME" \
    --policy-arn "$POLICY_ARN" 2>/dev/null || true

# Delete access keys
for key_id in $(awslocal iam list-access-keys --user-name "$USER_NAME" 2>/dev/null | jq -r '.AccessKeyMetadata[].AccessKeyId' 2>/dev/null || true); do
    awslocal iam delete-access-key --user-name "$USER_NAME" --access-key-id "$key_id" 2>/dev/null || true
done

# Delete user
awslocal iam delete-user --user-name "$USER_NAME" 2>/dev/null || true
echo "Deleted user: $USER_NAME"

# Delete policy
awslocal iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null || true
echo "Deleted policy: $POLICY_NAME"

# Clean up any test resources that may have been created
awslocal kinesis delete-stream --stream-name iam-test-stream 2>/dev/null || true
awslocal s3 rb s3://iam-test-bucket --force 2>/dev/null || true

# Clean up .env file
rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete"
