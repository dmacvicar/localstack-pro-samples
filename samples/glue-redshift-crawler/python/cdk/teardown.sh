#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

echo "=== Tearing down Glue Redshift Crawler (CDK) ==="

cd "$SCRIPT_DIR"

$CDK destroy --force 2>/dev/null || true

rm -f cdk-outputs.json
rm -rf cdk.out
rm -f ../scripts/.env

echo "Teardown complete!"
