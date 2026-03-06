#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"

cd "$SCRIPT_DIR"

if [ -f "terraform.tfstate" ]; then
    echo "Destroying Terraform resources..."
    terraform destroy -auto-approve -input=false
fi

rm -f "$SAMPLE_DIR/scripts/.env"
echo "Teardown complete"
