#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    TF="terraform"
fi

echo "=== Tearing down Glue Redshift Crawler (Terraform) ==="

cd "$SCRIPT_DIR"

$TF destroy -auto-approve -input=false 2>/dev/null || true

rm -f terraform.tfstate terraform.tfstate.backup
rm -rf .terraform .terraform.lock.hcl
rm -f ../scripts/.env

echo "Teardown complete!"
