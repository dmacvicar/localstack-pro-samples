#!/bin/bash
set -euo pipefail

# RDS Database Queries Terraform deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"

SUFFIX="${SUFFIX:-$(date +%s)}"
DB_INSTANCE_ID="rds-db-${SUFFIX}"

echo "Deploying RDS Database Queries with Terraform..."

cd "$SCRIPT_DIR"

# Initialize Terraform
tflocal init -input=false

# Apply configuration
tflocal apply -auto-approve -var="db_instance_id=${DB_INSTANCE_ID}"

# Get instance ID from terraform, then fetch actual connection details from RDS API
DB_INSTANCE_ID=$(tflocal output -raw db_instance_id)
DB_NAME=$(tflocal output -raw db_name)
DB_USER=$(tflocal output -raw db_user)
DB_PASSWORD="testpass123"

# Wait for instance to be available
echo "Waiting for RDS instance to be available..."
for i in {1..60}; do
    STATUS=$(awslocal rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --query "DBInstances[0].DBInstanceStatus" \
        --output text 2>/dev/null || echo "creating")
    if [ "$STATUS" = "available" ]; then
        echo "RDS instance is available"
        break
    fi
    echo "Status: $STATUS, waiting... ($i/60)"
    sleep 5
done

# Get actual connection details from RDS API
DB_HOST=$(awslocal rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query "DBInstances[0].Endpoint.Address" \
    --output text)

DB_PORT=$(awslocal rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query "DBInstances[0].Endpoint.Port" \
    --output text)

echo ""
echo "RDS instance deployed successfully!"
echo "  Instance ID: $DB_INSTANCE_ID"
echo "  Host: $DB_HOST"
echo "  Port: $DB_PORT"

# Write environment variables
mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" << EOF
DB_INSTANCE_ID=$DB_INSTANCE_ID
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
EOF

echo ""
echo "Environment written to $ENV_FILE"
