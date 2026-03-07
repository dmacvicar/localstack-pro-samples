#!/bin/bash
set -euo pipefail

# Transfer FTP to S3 CloudFormation deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="transfer-ftp-s3"

echo "Deploying Transfer FTP server with CloudFormation..."

cd "$SCRIPT_DIR"

# Deploy CloudFormation stack
awslocal cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file template.yml \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

# Get outputs
SERVER_ID=$(awslocal cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ServerId'].OutputValue" \
    --output text)

BUCKET_NAME=$(awslocal cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" \
    --output text)

USERNAME=$(awslocal cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='Username'].OutputValue" \
    --output text)

# Extract port from server ID (format: s-xxxNNNNN where NNNNN is the port)
FTP_PORT=$(echo "$SERVER_ID" | sed 's/s-[a-z]*//')

echo ""
echo "Transfer FTP server deployed successfully!"
echo "  Stack: $STACK_NAME"
echo "  Server ID: $SERVER_ID"
echo "  FTP Port: $FTP_PORT"
echo "  Bucket: $BUCKET_NAME"
echo "  Username: $USERNAME"

# Write environment variables
mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" << EOF
SERVER_ID=$SERVER_ID
FTP_PORT=$FTP_PORT
BUCKET_NAME=$BUCKET_NAME
USERNAME=$USERNAME
FTP_PASSWORD=12345
EOF

echo ""
echo "Environment written to $ENV_FILE"
