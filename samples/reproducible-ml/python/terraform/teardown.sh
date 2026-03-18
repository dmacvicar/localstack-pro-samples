#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    TF="terraform"
fi

echo "=== Tearing down Reproducible ML (Terraform) ==="

cd "$SCRIPT_DIR"

$TF destroy -auto-approve -input=false 2>/dev/null || true

rm -f ../scripts/.env
rm -f train.zip infer.zip
rm -rf .terraform .terraform.lock.hcl terraform.tfstate*

echo "Teardown complete!"
