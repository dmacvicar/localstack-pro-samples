#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"

cd "$SCRIPT_DIR"

echo "Destroying CDK stack..."
cdklocal destroy --force 2>/dev/null || true

# Clean up
rm -f outputs.json
rm -f "$SAMPLE_DIR/scripts/.env"

echo "Teardown complete!"
