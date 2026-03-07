#!/bin/bash
set -euo pipefail

# Glacier S3 Select CDK teardown script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="GlacierS3SelectStack"

echo "Tearing down Glacier S3 Select CDK resources..."

cd "$SCRIPT_DIR"

# Destroy stack
cdklocal destroy "$STACK_NAME" --force 2>/dev/null || true

# Clean up
rm -f "$ENV_FILE"
rm -f outputs.json
rm -rf cdk.out

echo "Teardown complete"
