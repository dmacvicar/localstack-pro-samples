#!/bin/bash
set -euo pipefail

# Glacier S3 Select Terraform teardown script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"

echo "Tearing down Glacier S3 Select Terraform resources..."

cd "$SCRIPT_DIR"

# Destroy resources
tflocal destroy -auto-approve 2>/dev/null || true

# Clean up
rm -f "$ENV_FILE"
rm -rf .terraform
rm -f .terraform.lock.hcl
rm -f terraform.tfstate*

echo "Teardown complete"
