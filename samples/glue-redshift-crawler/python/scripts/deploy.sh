#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use awslocal if available, otherwise aws with endpoint
if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

SUFFIX="${SUFFIX:-$(date +%s)}"
REDSHIFT_CLUSTER_ID="redshift-${SUFFIX}"
REDSHIFT_DB_NAME="db1"
REDSHIFT_TABLE_NAME="sales"
REDSHIFT_SCHEMA_NAME="public"
REDSHIFT_USERNAME="testuser"
REDSHIFT_PASSWORD="testPass123"
GLUE_DB_NAME="gluedb-${SUFFIX}"
GLUE_CONNECTION_NAME="glueconn-${SUFFIX}"
GLUE_CRAWLER_NAME="crawler-${SUFFIX}"

echo "=== Glue Redshift Crawler Sample ==="

# Step 1: Create Redshift cluster
echo "Creating Redshift cluster: ${REDSHIFT_CLUSTER_ID}..."
$AWSCLI redshift create-cluster \
    --cluster-identifier "$REDSHIFT_CLUSTER_ID" \
    --db-name "$REDSHIFT_DB_NAME" \
    --master-username "$REDSHIFT_USERNAME" \
    --master-user-password "$REDSHIFT_PASSWORD" \
    --node-type n1 > /dev/null

echo "Waiting for Redshift cluster to be available..."
for i in {1..60}; do
    STATUS=$($AWSCLI redshift describe-clusters \
        --cluster-identifier "$REDSHIFT_CLUSTER_ID" \
        --query "Clusters[0].ClusterStatus" \
        --output text 2>/dev/null || echo "creating")
    if [ "$STATUS" = "available" ]; then
        echo "Redshift cluster is available"
        break
    fi
    echo "Status: $STATUS, waiting... ($i/60)"
    sleep 5
done

# Get Redshift endpoint
REDSHIFT_HOST=$($AWSCLI redshift describe-clusters \
    --cluster-identifier "$REDSHIFT_CLUSTER_ID" \
    --query "Clusters[0].Endpoint.Address" \
    --output text)
REDSHIFT_PORT=$($AWSCLI redshift describe-clusters \
    --cluster-identifier "$REDSHIFT_CLUSTER_ID" \
    --query "Clusters[0].Endpoint.Port" \
    --output text)
REDSHIFT_URL="${REDSHIFT_HOST}:${REDSHIFT_PORT}"

# Step 2: Create Glue database
echo "Creating Glue database: ${GLUE_DB_NAME}..."
$AWSCLI glue create-database \
    --database-input "{\"Name\": \"${GLUE_DB_NAME}\"}"

# Step 3: Create Glue JDBC connection to Redshift
echo "Creating Glue connection: ${GLUE_CONNECTION_NAME}..."
$AWSCLI glue create-connection \
    --connection-input "{
        \"Name\": \"${GLUE_CONNECTION_NAME}\",
        \"ConnectionType\": \"JDBC\",
        \"ConnectionProperties\": {
            \"USERNAME\": \"${REDSHIFT_USERNAME}\",
            \"PASSWORD\": \"${REDSHIFT_PASSWORD}\",
            \"JDBC_CONNECTION_URL\": \"jdbc:redshift://${REDSHIFT_URL}/${REDSHIFT_DB_NAME}\"
        }
    }"

# Step 4: Create Glue crawler
echo "Creating Glue crawler: ${GLUE_CRAWLER_NAME}..."
$AWSCLI glue create-crawler \
    --name "$GLUE_CRAWLER_NAME" \
    --database-name "$GLUE_DB_NAME" \
    --targets "{
        \"JdbcTargets\": [{
            \"ConnectionName\": \"${GLUE_CONNECTION_NAME}\",
            \"Path\": \"${REDSHIFT_DB_NAME}/%/${REDSHIFT_TABLE_NAME}\"
        }]
    }" \
    --role "arn:aws:iam::000000000000:role/glue-crawler-role"

# Step 5: Create table in Redshift via Data API
echo "Creating table in Redshift..."
STATEMENT_ID=$($AWSCLI redshift-data execute-statement \
    --cluster-identifier "$REDSHIFT_CLUSTER_ID" \
    --database "$REDSHIFT_DB_NAME" \
    --sql "CREATE TABLE ${REDSHIFT_TABLE_NAME}(salesid integer not null, listid integer not null, sellerid integer not null, buyerid integer not null, eventid integer not null, dateid smallint not null, qtysold smallint not null, pricepaid decimal(8,2), commission decimal(8,2), saletime timestamp)" \
    --query "Id" --output text)

echo "Waiting for statement to finish..."
for i in {1..30}; do
    STMT_STATUS=$($AWSCLI redshift-data describe-statement \
        --id "$STATEMENT_ID" \
        --query "Status" --output text 2>/dev/null || echo "SUBMITTED")
    if [ "$STMT_STATUS" = "FINISHED" ]; then
        echo "Statement completed"
        break
    fi
    if [ "$STMT_STATUS" = "FAILED" ]; then
        echo "Statement failed!"
        $AWSCLI redshift-data describe-statement --id "$STATEMENT_ID"
        exit 1
    fi
    echo "Statement status: $STMT_STATUS, waiting... ($i/30)"
    sleep 2
done

# Step 6: Run the crawler
echo "Starting crawler..."
$AWSCLI glue start-crawler --name "$GLUE_CRAWLER_NAME"

echo "Waiting for crawler to finish..."
for i in {1..60}; do
    CRAWLER_STATE=$($AWSCLI glue get-crawler \
        --name "$GLUE_CRAWLER_NAME" \
        --query "Crawler.State" --output text 2>/dev/null || echo "RUNNING")
    if [ "$CRAWLER_STATE" = "READY" ]; then
        echo "Crawler completed"
        break
    fi
    echo "Crawler state: $CRAWLER_STATE, waiting... ($i/60)"
    sleep 5
done

# Expected table name from crawler
GLUE_TABLE_NAME="${REDSHIFT_DB_NAME}_${REDSHIFT_SCHEMA_NAME}_${REDSHIFT_TABLE_NAME}"

# Save configuration
cat > "$SCRIPT_DIR/.env" << EOF
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

echo ""
echo "Deployment complete!"
echo "Redshift: ${REDSHIFT_CLUSTER_ID}"
echo "Glue DB: ${GLUE_DB_NAME}"
echo "Crawler: ${GLUE_CRAWLER_NAME}"
echo "Glue Table: ${GLUE_TABLE_NAME}"
