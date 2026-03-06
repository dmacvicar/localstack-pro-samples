#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"

SUFFIX=$(date +%s)
BUCKET_NAME="transfer-files-${SUFFIX}"
USERNAME="user-${SUFFIX}"

echo "Creating S3 bucket: $BUCKET_NAME"
awslocal s3 mb "s3://$BUCKET_NAME"

echo "Creating Transfer FTP server..."
SERVER_RESPONSE=$(awslocal transfer create-server \
    --endpoint-type PUBLIC \
    --identity-provider-type SERVICE_MANAGED \
    --protocols FTP)

SERVER_ID=$(echo "$SERVER_RESPONSE" | jq -r '.ServerId')

# Extract port from server ID (format: s-xxxNNNNN where NNNNN is the port)
FTP_PORT=$(echo "$SERVER_ID" | sed 's/s-[a-z]*//')

echo "Creating Transfer user: $USERNAME"
awslocal transfer create-user \
    --server-id "$SERVER_ID" \
    --user-name "$USERNAME" \
    --home-directory "$BUCKET_NAME" \
    --home-directory-type PATH \
    --role "arn:aws:iam::000000000000:role/transfer-role"

# Save configuration for tests
cat > "$SCRIPT_DIR/.env" << EOF
BUCKET_NAME=$BUCKET_NAME
SERVER_ID=$SERVER_ID
FTP_PORT=$FTP_PORT
USERNAME=$USERNAME
FTP_PASSWORD=12345
EOF

echo ""
echo "Deployment complete!"
echo "Server ID: $SERVER_ID"
echo "FTP Port: $FTP_PORT"
echo "Bucket: $BUCKET_NAME"
echo "Username: $USERNAME"
