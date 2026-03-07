#!/bin/bash
set -euo pipefail

# Glacier S3 Select CDK deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="GlacierS3SelectStack"
LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"

echo "Deploying Glacier S3 Select with CDK..."

cd "$SCRIPT_DIR"

# Install CDK dependencies
pip install -q -r requirements.txt

# Bootstrap CDK (if needed)
cdklocal bootstrap --quiet 2>/dev/null || true

# Deploy
cdklocal deploy "$STACK_NAME" --require-approval never --outputs-file outputs.json

# Extract outputs
BUCKET_NAME=$(jq -r ".\"$STACK_NAME\".BucketName" outputs.json)
RESULTS_BUCKET=$(jq -r ".\"$STACK_NAME\".ResultsBucket" outputs.json)
VAULT_NAME=$(jq -r ".\"$STACK_NAME\".VaultName" outputs.json)

# Upload archive to Glacier (CDK can't do this directly)
echo "Uploading archive to Glacier vault..."
ARCHIVE_ID=$(awslocal glacier upload-archive \
    --vault-name "$VAULT_NAME" \
    --account-id - \
    --body "$SAMPLE_DIR/data.csv" \
    --endpoint-url "$LOCALSTACK_ENDPOINT" \
    | jq -r '.archiveId')

echo ""
echo "Glacier S3 Select deployed successfully!"
echo "  Bucket: $BUCKET_NAME"
echo "  Results Bucket: $RESULTS_BUCKET"
echo "  Vault: $VAULT_NAME"
echo "  Archive ID: $ARCHIVE_ID"

# Write environment variables
mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" << EOF
BUCKET_NAME=$BUCKET_NAME
RESULTS_BUCKET=$RESULTS_BUCKET
VAULT_NAME=$VAULT_NAME
ARCHIVE_ID=$ARCHIVE_ID
EOF

echo ""
echo "Environment written to $ENV_FILE"
