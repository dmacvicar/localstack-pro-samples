#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
SUFFIX="${SUFFIX:-$(date +%s)}"

BUCKET_NAME="glacier-s3-select-${SUFFIX}"
VAULT_NAME="vault-${SUFFIX}"
RESULTS_BUCKET="glacier-results-${SUFFIX}"

LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"

echo "Creating S3 buckets..."
awslocal s3 mb "s3://${BUCKET_NAME}" --endpoint-url "$LOCALSTACK_ENDPOINT"
awslocal s3 mb "s3://${RESULTS_BUCKET}" --endpoint-url "$LOCALSTACK_ENDPOINT"

echo "Uploading CSV data file..."
awslocal s3 cp "$SAMPLE_DIR/data.csv" "s3://${BUCKET_NAME}/data.csv" --endpoint-url "$LOCALSTACK_ENDPOINT"

echo "Creating Glacier vault..."
awslocal glacier create-vault --account-id - --vault-name "$VAULT_NAME" --endpoint-url "$LOCALSTACK_ENDPOINT"

echo "Uploading archive to Glacier vault..."
ARCHIVE_ID=$(awslocal glacier upload-archive \
    --vault-name "$VAULT_NAME" \
    --account-id - \
    --body "$SAMPLE_DIR/data.csv" \
    --endpoint-url "$LOCALSTACK_ENDPOINT" \
    | jq -r '.archiveId')

# Save configuration for tests
cat > "$SCRIPT_DIR/.env" << EOF
BUCKET_NAME=$BUCKET_NAME
VAULT_NAME=$VAULT_NAME
RESULTS_BUCKET=$RESULTS_BUCKET
ARCHIVE_ID=$ARCHIVE_ID
EOF

echo ""
echo "Deployment complete!"
echo "Bucket: $BUCKET_NAME"
echo "Vault: $VAULT_NAME"
echo "Results Bucket: $RESULTS_BUCKET"
echo "Archive ID: $ARCHIVE_ID"
