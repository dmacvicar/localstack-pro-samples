#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"

cd "$SCRIPT_DIR"

if [ ! -f "terraform.tfstate" ]; then
    echo "No Terraform state found. Nothing to tear down."
    exit 0
fi

echo "Destroying Terraform resources..."
tflocal destroy -auto-approve

# Clean up .env file
rm -f "$SAMPLE_DIR/scripts/.env"

echo "Teardown complete!"
