#!/bin/bash
set -euo pipefail

# RDS Database Queries CDK deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="RdsDbQueriesStack"

SUFFIX="${SUFFIX:-$(date +%s)}"
export DB_INSTANCE_ID="rds-db-${SUFFIX}"
export DB_NAME="testdb"
export DB_USER="testuser"
export DB_PASSWORD="testpass123"

echo "Deploying RDS Database Queries with CDK..."

cd "$SCRIPT_DIR"

# Install CDK dependencies
pip install -q -r requirements.txt

# Bootstrap CDK (if needed)
cdklocal bootstrap --quiet 2>/dev/null || true

# Deploy
cdklocal deploy "$STACK_NAME" --require-approval never --outputs-file outputs.json

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

# Get connection details from RDS API
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
