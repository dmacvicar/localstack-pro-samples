#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    TF="terraform"
fi

echo "=== Tearing down Glue MSK Schema Registry (Terraform) ==="

cd "$SCRIPT_DIR"

$TF destroy -auto-approve -input=false 2>/dev/null || true

rm -f ../scripts/.env
rm -rf .terraform terraform.tfstate* .terraform.lock.hcl

echo "Teardown complete!"
