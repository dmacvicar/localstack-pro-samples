#!/bin/bash
set -euo pipefail

# Transfer FTP to S3 Terraform deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"

echo "Deploying Transfer FTP server with Terraform..."

cd "$SCRIPT_DIR"

# Initialize Terraform
tflocal init -input=false

# Apply configuration
tflocal apply -auto-approve

# Extract outputs
SERVER_ID=$(tflocal output -raw server_id)
BUCKET_NAME=$(tflocal output -raw bucket_name)
USERNAME=$(tflocal output -raw username)

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
