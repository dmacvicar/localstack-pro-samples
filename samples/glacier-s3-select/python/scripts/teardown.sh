#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"

    echo "Deleting S3 bucket ${BUCKET_NAME}..."
    awslocal s3 rb "s3://${BUCKET_NAME}" --force --endpoint-url "$LOCALSTACK_ENDPOINT" 2>/dev/null || true

    echo "Deleting results bucket ${RESULTS_BUCKET}..."
    awslocal s3 rb "s3://${RESULTS_BUCKET}" --force --endpoint-url "$LOCALSTACK_ENDPOINT" 2>/dev/null || true

    echo "Deleting Glacier vault ${VAULT_NAME}..."
    awslocal glacier delete-vault --account-id - --vault-name "$VAULT_NAME" --endpoint-url "$LOCALSTACK_ENDPOINT" 2>/dev/null || true

    rm -f "$SCRIPT_DIR/.env"
fi

echo "Teardown complete"
