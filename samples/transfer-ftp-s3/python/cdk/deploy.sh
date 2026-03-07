#!/bin/bash
set -euo pipefail

# Transfer FTP to S3 CDK deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="TransferFtpS3Stack"

echo "Deploying Transfer FTP server with CDK..."

cd "$SCRIPT_DIR"

# Install CDK dependencies
pip install -q -r requirements.txt

# Bootstrap CDK (if needed)
cdklocal bootstrap --quiet 2>/dev/null || true

# Deploy
cdklocal deploy "$STACK_NAME" --require-approval never --outputs-file outputs.json

# Extract outputs
SERVER_ID=$(jq -r ".\"$STACK_NAME\".ServerId" outputs.json)
BUCKET_NAME=$(jq -r ".\"$STACK_NAME\".BucketName" outputs.json)
USERNAME=$(jq -r ".\"$STACK_NAME\".Username" outputs.json)

# Extract port from server ID (format: s-xxxNNNNN where NNNNN is the port)
FTP_PORT=$(echo "$SERVER_ID" | sed 's/s-[a-z]*//')

echo ""
echo "Transfer FTP server deployed successfully!"
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
