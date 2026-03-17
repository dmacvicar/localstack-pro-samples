#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use tflocal if available, otherwise terraform
if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    TF="terraform"
fi

echo "=== Deploying AppSync GraphQL API (Terraform) ==="

cd "$SCRIPT_DIR"

$TF init -input=false
$TF apply -auto-approve -input=false

# Extract outputs
API_ID=$($TF output -raw api_id)
API_URL=$($TF output -raw api_url)
API_KEY=$($TF output -raw api_key)
API_NAME=$($TF output -raw api_name)
TABLE_NAME=$($TF output -raw table_name)
DB_CLUSTER_ID=$($TF output -raw db_cluster_id)
DB_CLUSTER_ARN=$($TF output -raw db_cluster_arn)
DB_NAME=$($TF output -raw db_name)
SECRET_ARN=$($TF output -raw secret_arn)
ROLE_ARN=$($TF output -raw role_arn)

# Save to shared .env
cat > "$SCRIPT_DIR/../scripts/.env" << EOF
API_ID=$API_ID
API_URL=$API_URL
API_KEY=$API_KEY
API_NAME=$API_NAME
TABLE_NAME=$TABLE_NAME
DB_CLUSTER_ID=$DB_CLUSTER_ID
DB_CLUSTER_ARN=$DB_CLUSTER_ARN
DB_NAME=$DB_NAME
SECRET_ARN=$SECRET_ARN
ROLE_ARN=$ROLE_ARN
EOF

echo ""
echo "Deployment complete!"
echo "API ID: ${API_ID}"
echo "API URL: ${API_URL}"
