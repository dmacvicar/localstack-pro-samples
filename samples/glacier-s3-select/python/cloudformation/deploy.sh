#!/bin/bash
set -euo pipefail

# Glacier S3 Select CloudFormation deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="glacier-s3-select"
LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"

echo "Deploying Glacier S3 Select with CloudFormation..."

cd "$SCRIPT_DIR"

# Deploy CloudFormation stack
awslocal cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file template.yml \
    --no-fail-on-empty-changeset

# Get outputs
BUCKET_NAME=$(awslocal cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" \
    --output text)

RESULTS_BUCKET=$(awslocal cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ResultsBucket'].OutputValue" \
    --output text)

VAULT_NAME=$(awslocal cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='VaultName'].OutputValue" \
    --output text)

# Upload CSV data to S3
echo "Uploading CSV data file..."
awslocal s3 cp "$SAMPLE_DIR/data.csv" "s3://${BUCKET_NAME}/data.csv" --endpoint-url "$LOCALSTACK_ENDPOINT"

# Upload archive to Glacier
echo "Uploading archive to Glacier vault..."
ARCHIVE_ID=$(awslocal glacier upload-archive \
    --vault-name "$VAULT_NAME" \
    --account-id - \
    --body "$SAMPLE_DIR/data.csv" \
    --endpoint-url "$LOCALSTACK_ENDPOINT" \
    | jq -r '.archiveId')

echo ""
echo "Glacier S3 Select deployed successfully!"
echo "  Stack: $STACK_NAME"
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
