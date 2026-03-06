#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

if [ -n "${SERVER_ID:-}" ] && [ -n "${USERNAME:-}" ]; then
    echo "Deleting Transfer user: $USERNAME"
    awslocal transfer delete-user --server-id "$SERVER_ID" --user-name "$USERNAME" 2>/dev/null || true
fi

if [ -n "${SERVER_ID:-}" ]; then
    echo "Deleting Transfer server: $SERVER_ID"
    awslocal transfer delete-server --server-id "$SERVER_ID" 2>/dev/null || true
fi

if [ -n "${BUCKET_NAME:-}" ]; then
    echo "Deleting S3 bucket: $BUCKET_NAME"
    awslocal s3 rb "s3://$BUCKET_NAME" --force 2>/dev/null || true
fi

rm -f "$SCRIPT_DIR/.env"
echo "Teardown complete"
