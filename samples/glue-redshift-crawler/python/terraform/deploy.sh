#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    TF="terraform"
fi

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

echo "=== Deploying Glue Redshift Crawler (Terraform) ==="

cd "$SCRIPT_DIR"

$TF init -input=false
$TF apply -auto-approve -input=false

# Extract outputs
REDSHIFT_CLUSTER_ID=$($TF output -raw redshift_cluster_id)
REDSHIFT_DB_NAME=$($TF output -raw redshift_db_name)
REDSHIFT_TABLE_NAME=$($TF output -raw redshift_table_name)
REDSHIFT_SCHEMA_NAME=$($TF output -raw redshift_schema_name)
REDSHIFT_USERNAME=$($TF output -raw redshift_username)
REDSHIFT_PASSWORD=$($TF output -raw redshift_password)
REDSHIFT_HOST=$($TF output -raw redshift_host)
REDSHIFT_PORT=$($TF output -raw redshift_port)
GLUE_DB_NAME=$($TF output -raw glue_db_name)
GLUE_CONNECTION_NAME=$($TF output -raw glue_connection_name)
GLUE_CRAWLER_NAME=$($TF output -raw glue_crawler_name)
GLUE_TABLE_NAME=$($TF output -raw glue_table_name)

# Create table in Redshift and run crawler (not managed by Terraform)
echo "Creating table in Redshift via Data API..."
STATEMENT_ID=$($AWSCLI redshift-data execute-statement \
    --cluster-identifier "$REDSHIFT_CLUSTER_ID" \
    --database "$REDSHIFT_DB_NAME" \
    --sql "CREATE TABLE IF NOT EXISTS sales(salesid integer not null, listid integer not null, sellerid integer not null, buyerid integer not null, eventid integer not null, dateid smallint not null, qtysold smallint not null, pricepaid decimal(8,2), commission decimal(8,2), saletime timestamp)" \
    --query "Id" --output text)

for i in {1..30}; do
    STMT_STATUS=$($AWSCLI redshift-data describe-statement --id "$STATEMENT_ID" --query "Status" --output text 2>/dev/null || echo "SUBMITTED")
    [ "$STMT_STATUS" = "FINISHED" ] && break
    sleep 2
done

echo "Starting crawler..."
$AWSCLI glue start-crawler --name "$GLUE_CRAWLER_NAME"

for i in {1..60}; do
    CRAWLER_STATE=$($AWSCLI glue get-crawler --name "$GLUE_CRAWLER_NAME" --query "Crawler.State" --output text 2>/dev/null || echo "RUNNING")
    [ "$CRAWLER_STATE" = "READY" ] && break
    sleep 5
done

# Save to shared .env
cat > "$SCRIPT_DIR/../scripts/.env" << EOF
REDSHIFT_CLUSTER_ID=$REDSHIFT_CLUSTER_ID
REDSHIFT_DB_NAME=$REDSHIFT_DB_NAME
REDSHIFT_TABLE_NAME=$REDSHIFT_TABLE_NAME
REDSHIFT_SCHEMA_NAME=$REDSHIFT_SCHEMA_NAME
REDSHIFT_USERNAME=$REDSHIFT_USERNAME
REDSHIFT_PASSWORD=$REDSHIFT_PASSWORD
REDSHIFT_HOST=$REDSHIFT_HOST
REDSHIFT_PORT=$REDSHIFT_PORT
GLUE_DB_NAME=$GLUE_DB_NAME
GLUE_CONNECTION_NAME=$GLUE_CONNECTION_NAME
GLUE_CRAWLER_NAME=$GLUE_CRAWLER_NAME
GLUE_TABLE_NAME=$GLUE_TABLE_NAME
EOF

echo "Deployment complete!"
