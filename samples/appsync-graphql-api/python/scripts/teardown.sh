#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use awslocal if available, otherwise aws with endpoint
if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

# Load environment
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

echo "=== Tearing down AppSync GraphQL API ==="

# Delete AppSync API (includes data sources and resolvers)
if [ -n "${API_ID:-}" ]; then
    echo "Deleting AppSync API..."
    $AWSCLI appsync delete-graphql-api --api-id "$API_ID" 2>/dev/null || true
fi

# Delete DynamoDB table
if [ -n "${TABLE_NAME:-}" ]; then
    echo "Deleting DynamoDB table..."
    $AWSCLI dynamodb delete-table --table-name "$TABLE_NAME" 2>/dev/null || true
fi

# Delete RDS cluster
if [ -n "${DB_CLUSTER_ID:-}" ]; then
    echo "Deleting RDS cluster..."
    $AWSCLI rds delete-db-cluster \
        --db-cluster-identifier "$DB_CLUSTER_ID" \
        --skip-final-snapshot 2>/dev/null || true
fi

# Delete secret
if [ -n "${SECRET_NAME:-}" ]; then
    echo "Deleting Secrets Manager secret..."
    $AWSCLI secretsmanager delete-secret \
        --secret-id "$SECRET_NAME" \
        --force-delete-without-recovery 2>/dev/null || true
fi

# Delete IAM role
if [ -n "${ROLE_NAME:-}" ]; then
    echo "Deleting IAM role..."
    $AWSCLI iam detach-role-policy --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" 2>/dev/null || true
    $AWSCLI iam detach-role-policy --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonRDSDataFullAccess" 2>/dev/null || true
    $AWSCLI iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true
fi

rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete!"
