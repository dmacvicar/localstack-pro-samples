#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
STAGE="local"

echo "Tearing down API Gateway WebSockets Sample (scripts)"

cd "$PROJECT_DIR"

# Remove with Serverless if .serverless exists
if [[ -d ".serverless" ]]; then
    echo "Removing Serverless deployment..."
    npx serverless remove --stage "$STAGE" --region "$REGION" 2>/dev/null || true
fi

# Clean up .env
rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete!"
