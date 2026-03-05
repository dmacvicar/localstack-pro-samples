#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Tearing down Lambda Container Image Sample (terraform)"

cd "$SCRIPT_DIR"

if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    TF="terraform"
fi

# Destroy all resources
$TF destroy -auto-approve -input=false 2>/dev/null || true

# Clean up state files
rm -f terraform.tfstate terraform.tfstate.backup
rm -rf .terraform .terraform.lock.hcl

# Clean up .env
rm -f "$PROJECT_DIR/scripts/.env"

echo "Teardown complete!"
