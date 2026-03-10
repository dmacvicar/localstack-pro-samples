#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
else
    echo "No .env file found. Nothing to tear down."
    exit 0
fi

echo "Cleaning up Glue ETL resources..."

if [ -n "${JOB_NAME:-}" ]; then
    echo "Deleting Glue job: $JOB_NAME"
    awslocal glue delete-job --job-name "$JOB_NAME" 2>/dev/null || true
fi

if [ -n "${CONNECTION_NAME:-}" ]; then
    echo "Deleting Glue connection: $CONNECTION_NAME"
    awslocal glue delete-connection --connection-name "$CONNECTION_NAME" 2>/dev/null || true
fi

echo "Deleting Glue tables..."
for table in memberships_json persons_json organizations_json; do
    awslocal glue delete-table --database-name legislators --name "$table" 2>/dev/null || true
done
echo "Deleting Glue database: legislators"
awslocal glue delete-database --name legislators 2>/dev/null || true

if [ -n "${CLUSTER_IDENTIFIER:-}" ]; then
    echo "Deleting RDS cluster: $CLUSTER_IDENTIFIER"
    awslocal rds delete-db-cluster \
        --db-cluster-identifier "$CLUSTER_IDENTIFIER" \
        --skip-final-snapshot 2>/dev/null || true
fi

awslocal secretsmanager delete-secret \
    --secret-id pass \
    --force-delete-without-recovery 2>/dev/null || true

for bucket in "${BUCKET:-}" "${TARGET_BUCKET:-}"; do
    if [ -n "$bucket" ]; then
        echo "Deleting S3 bucket: $bucket"
        awslocal s3 rb "s3://$bucket" --force 2>/dev/null || true
    fi
done

rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete!"
