#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

echo "=== Deploying Glue Redshift Crawler (CDK) ==="

cd "$SCRIPT_DIR"

uv pip install --system -r requirements.txt 2>/dev/null || pip install -r requirements.txt
$CDK bootstrap 2>/dev/null || true
$CDK deploy --require-approval never --outputs-file cdk-outputs.json

STACK_OUTPUT=$(cat cdk-outputs.json | jq -r '.GlueRedshiftCrawlerStack')

REDSHIFT_CLUSTER_ID=$(echo "$STACK_OUTPUT" | jq -r '.RedshiftClusterId')
REDSHIFT_DB_NAME=$(echo "$STACK_OUTPUT" | jq -r '.RedshiftDBName')
GLUE_CRAWLER_NAME=$(echo "$STACK_OUTPUT" | jq -r '.GlueCrawlerName')

# Create table in Redshift and run crawler
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

cat > "$SCRIPT_DIR/../scripts/.env" << EOF
REDSHIFT_CLUSTER_ID=$(echo "$STACK_OUTPUT" | jq -r '.RedshiftClusterId')
REDSHIFT_DB_NAME=$(echo "$STACK_OUTPUT" | jq -r '.RedshiftDBName')
REDSHIFT_TABLE_NAME=$(echo "$STACK_OUTPUT" | jq -r '.RedshiftTableName')
REDSHIFT_SCHEMA_NAME=$(echo "$STACK_OUTPUT" | jq -r '.RedshiftSchemaName')
REDSHIFT_USERNAME=$(echo "$STACK_OUTPUT" | jq -r '.RedshiftUsername')
REDSHIFT_HOST=$(echo "$STACK_OUTPUT" | jq -r '.RedshiftHost')
REDSHIFT_PORT=$(echo "$STACK_OUTPUT" | jq -r '.RedshiftPort')
GLUE_DB_NAME=$(echo "$STACK_OUTPUT" | jq -r '.GlueDBName')
GLUE_CONNECTION_NAME=$(echo "$STACK_OUTPUT" | jq -r '.GlueConnectionName')
GLUE_CRAWLER_NAME=$(echo "$STACK_OUTPUT" | jq -r '.GlueCrawlerName')
GLUE_TABLE_NAME=$(echo "$STACK_OUTPUT" | jq -r '.GlueTableName')
EOF

echo "Deployment complete!"
