#!/bin/bash
set -euo pipefail

# CloudWatch Metrics Terraform teardown script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"

echo "Tearing down CloudWatch metrics Terraform resources..."

cd "$SCRIPT_DIR"

# Destroy resources
if [ -f "terraform.tfstate" ]; then
    tflocal destroy -auto-approve -input=false
fi

# Clean up
rm -f "$ENV_FILE"
rm -f terraform.tfstate terraform.tfstate.backup
rm -rf .terraform .terraform.lock.hcl
rm -f handler.zip

echo "Teardown complete"
