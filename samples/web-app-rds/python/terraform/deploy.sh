#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Web App RDS Sample via Terraform"

cd "$SCRIPT_DIR"

# Determine Terraform CLI to use
if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    echo "Warning: tflocal not found, using terraform with manual endpoint config"
    TF="terraform"
fi

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

# Initialize Terraform
echo "Step 1: Initializing Terraform..."
$TF init -input=false

# Apply configuration
echo "Step 2: Applying Terraform configuration..."
$TF apply -auto-approve -input=false

# Wait for RDS to be available
echo "Step 3: Waiting for RDS instance..."
DB_INSTANCE_ID=$($TF output -raw db_instance_id)
MAX_ATTEMPTS=30
ATTEMPT=1

while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
    STATUS=$($AWS rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "pending")

    if [[ "$STATUS" == "available" ]]; then
        echo "  RDS instance is available"
        break
    fi
    echo "  Status: $STATUS (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done

# Extract outputs
echo "Step 4: Extracting outputs..."
FUNCTION_NAME=$($TF output -raw function_name)
FUNCTION_URL=$($TF output -raw function_url)
LAMBDA_ARN=$($TF output -raw function_arn)
DB_HOST=$($TF output -raw db_host)
DB_PORT=$($TF output -raw db_port)

# Save config for test script (shared with scripts/)
cat > "$SCRIPT_DIR/../scripts/.env" << EOF
FUNCTION_NAME=$FUNCTION_NAME
FUNCTION_URL=$FUNCTION_URL
LAMBDA_ARN=$LAMBDA_ARN
DB_INSTANCE_ID=$DB_INSTANCE_ID
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=appdb
DB_USER=admin
REGION=$REGION
EOF

echo ""
echo "Deployment complete!"
echo "  Function Name: $FUNCTION_NAME"
echo "  Function URL: $FUNCTION_URL"
echo "  RDS Instance: $DB_INSTANCE_ID"
echo ""
echo "Run tests with: ../scripts/test.sh"
