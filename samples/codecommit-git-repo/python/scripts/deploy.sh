#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"

SUFFIX=$(date +%s)
REPO_NAME="repo-${SUFFIX}"

echo "Creating CodeCommit repository: $REPO_NAME"
REPO_RESPONSE=$(awslocal codecommit create-repository --repository-name "$REPO_NAME")

REPO_ARN=$(echo "$REPO_RESPONSE" | jq -r '.repositoryMetadata.Arn')
REPO_ID=$(echo "$REPO_RESPONSE" | jq -r '.repositoryMetadata.repositoryId')
CLONE_URL_SSH=$(echo "$REPO_RESPONSE" | jq -r '.repositoryMetadata.cloneUrlSsh')
CLONE_URL_HTTP=$(echo "$REPO_RESPONSE" | jq -r '.repositoryMetadata.cloneUrlHttp')

# Save configuration for tests
cat > "$SCRIPT_DIR/.env" << EOF
REPO_NAME=$REPO_NAME
REPO_ARN=$REPO_ARN
REPO_ID=$REPO_ID
CLONE_URL_SSH=$CLONE_URL_SSH
CLONE_URL_HTTP=$CLONE_URL_HTTP
EOF

echo ""
echo "Deployment complete!"
echo "Repository: $REPO_NAME"
echo "Clone URL SSH: $CLONE_URL_SSH"
echo "Clone URL HTTP: $CLONE_URL_HTTP"
