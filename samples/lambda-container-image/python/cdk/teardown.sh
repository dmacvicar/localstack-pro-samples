#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="LambdaContainerImageStack"

echo "Tearing down Lambda Container Image Sample (cdk)"

cd "$SCRIPT_DIR"

if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

# Destroy CDK stack
$CDK destroy --force 2>/dev/null || true

# Clean up outputs
rm -f cdk-outputs.json cdk.out

# Clean up .env
rm -f "$PROJECT_DIR/scripts/.env"

echo "Teardown complete!"
