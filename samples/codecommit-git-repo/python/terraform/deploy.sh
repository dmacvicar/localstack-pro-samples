#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"

cd "$SCRIPT_DIR"

echo "Initializing Terraform..."
terraform init -input=false

echo "Applying Terraform configuration..."
terraform apply -auto-approve -input=false

# Extract outputs
REPO_NAME=$(terraform output -raw repo_name)
REPO_ARN=$(terraform output -raw repo_arn)
REPO_ID=$(terraform output -raw repo_id)
CLONE_URL_SSH=$(terraform output -raw clone_url_ssh)
CLONE_URL_HTTP=$(terraform output -raw clone_url_http)

# Save configuration for tests
cat > "$SAMPLE_DIR/scripts/.env" << EOF
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
