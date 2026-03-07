#!/bin/bash
set -euo pipefail

# EC2 Docker Instances Terraform teardown script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"

echo "Tearing down EC2 Docker instances Terraform resources..."

cd "$SCRIPT_DIR"

# Destroy resources
if [ -f "terraform.tfstate" ]; then
    tflocal destroy -auto-approve -input=false || true
fi

# Clean up
rm -f "$ENV_FILE"
rm -f terraform.tfstate terraform.tfstate.backup
rm -rf .terraform .terraform.lock.hcl

echo "Teardown complete"
