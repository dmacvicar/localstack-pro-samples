#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

STACK_NAME="glue-redshift-crawler"

echo "=== Deploying Glue Redshift Crawler (CloudFormation) ==="

$AWSCLI cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file "$SCRIPT_DIR/template.yml" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset 2>/dev/null || \
$AWSCLI cloudformation create-stack \
    --stack-name "$STACK_NAME" \
    --template-body "file://$SCRIPT_DIR/template.yml" \
    --capabilities CAPABILITY_NAMED_IAM

echo "Waiting for stack..."
$AWSCLI cloudformation wait stack-create-complete --stack-name "$STACK_NAME" 2>/dev/null || \
$AWSCLI cloudformation wait stack-update-complete --stack-name "$STACK_NAME" 2>/dev/null || true

OUTPUTS=$($AWSCLI cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs')
get_output() { echo "$OUTPUTS" | jq -r ".[] | select(.OutputKey==\"$1\") | .OutputValue"; }

REDSHIFT_CLUSTER_ID=$(get_output "RedshiftClusterId")
REDSHIFT_DB_NAME=$(get_output "RedshiftDBName")
GLUE_CRAWLER_NAME=$(get_output "GlueCrawlerName")

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
REDSHIFT_CLUSTER_ID=$(get_output "RedshiftClusterId")
REDSHIFT_DB_NAME=$(get_output "RedshiftDBName")
REDSHIFT_TABLE_NAME=$(get_output "RedshiftTableName")
REDSHIFT_SCHEMA_NAME=$(get_output "RedshiftSchemaName")
REDSHIFT_USERNAME=$(get_output "RedshiftUsername")
REDSHIFT_HOST=$(get_output "RedshiftHost")
REDSHIFT_PORT=$(get_output "RedshiftPort")
GLUE_DB_NAME=$(get_output "GlueDBName")
GLUE_CONNECTION_NAME=$(get_output "GlueConnectionName")
GLUE_CRAWLER_NAME=$(get_output "GlueCrawlerName")
GLUE_TABLE_NAME=$(get_output "GlueTableName")
STACK_NAME=$STACK_NAME
EOF

echo "Deployment complete!"
