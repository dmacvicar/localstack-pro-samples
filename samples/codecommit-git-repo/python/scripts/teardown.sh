#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

if [ -n "${REPO_NAME:-}" ]; then
    echo "Deleting CodeCommit repository: $REPO_NAME"
    awslocal codecommit delete-repository --repository-name "$REPO_NAME" 2>/dev/null || true
fi

rm -f "$SCRIPT_DIR/.env"
echo "Teardown complete"
