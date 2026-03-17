#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use awslocal if available, otherwise aws with endpoint
if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
SUFFIX="${SUFFIX:-$(date +%s)}"
TABLE_NAME="appsync-table-${SUFFIX}"
DB_CLUSTER_ID="appsync-rds-${SUFFIX}"
DB_NAME="testappsync"
DB_USER="testuser"
DB_PASSWORD="testpass"
API_NAME="appsync-api-${SUFFIX}"
SECRET_NAME="appsync-rds-secret-${SUFFIX}"

echo "=== AppSync GraphQL API Sample ==="

# Step 1: Create DynamoDB table
echo "Creating DynamoDB table: ${TABLE_NAME}..."
$AWSCLI dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST > /dev/null

# Step 2: Create RDS Aurora PostgreSQL cluster
echo "Creating RDS Aurora PostgreSQL cluster: ${DB_CLUSTER_ID}..."
echo "Note: First run may take time to download PostgreSQL Docker image"
$AWSCLI rds create-db-cluster \
    --db-cluster-identifier "$DB_CLUSTER_ID" \
    --engine aurora-postgresql \
    --master-username "$DB_USER" \
    --master-user-password "$DB_PASSWORD" \
    --database-name "$DB_NAME" > /dev/null

echo "Waiting for RDS cluster to be available..."
for i in {1..60}; do
    STATUS=$($AWSCLI rds describe-db-clusters \
        --db-cluster-identifier "$DB_CLUSTER_ID" \
        --query "DBClusters[0].Status" \
        --output text 2>/dev/null || echo "creating")
    if [ "$STATUS" = "available" ]; then
        echo "RDS cluster is available"
        break
    fi
    echo "Status: $STATUS, waiting... ($i/60)"
    sleep 5
done

# Get cluster ARN
DB_CLUSTER_ARN=$($AWSCLI rds describe-db-clusters \
    --db-cluster-identifier "$DB_CLUSTER_ID" \
    --query "DBClusters[0].DBClusterArn" \
    --output text)

# Step 3: Create Secrets Manager secret for RDS
echo "Creating Secrets Manager secret..."
SECRET_ARN=$($AWSCLI secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --secret-string "$DB_PASSWORD" \
    --query "ARN" --output text)

# Step 4: Create IAM role for AppSync
echo "Creating IAM role for AppSync..."
ROLE_NAME="appsync-role-${SUFFIX}"
$AWSCLI iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "appsync.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }' > /dev/null

$AWSCLI iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" 2>/dev/null || true
$AWSCLI iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonRDSDataFullAccess" 2>/dev/null || true

ROLE_ARN=$($AWSCLI iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text)

# Step 5: Create AppSync GraphQL API
echo "Creating AppSync GraphQL API: ${API_NAME}..."
API_RESPONSE=$($AWSCLI appsync create-graphql-api \
    --name "$API_NAME" \
    --authentication-type API_KEY)
API_ID=$(echo "$API_RESPONSE" | jq -r '.graphqlApi.apiId')
API_URL=$(echo "$API_RESPONSE" | jq -r '.graphqlApi.uris.GRAPHQL')
echo "API ID: ${API_ID}"
echo "API URL: ${API_URL}"

# Step 6: Create API key
echo "Creating API key..."
API_KEY=$($AWSCLI appsync create-api-key \
    --api-id "$API_ID" \
    --query "apiKey.id" --output text)
echo "API Key: ${API_KEY}"

# Step 7: Upload GraphQL schema
echo "Uploading GraphQL schema..."
$AWSCLI appsync start-schema-creation \
    --api-id "$API_ID" \
    --definition "fileb://$SAMPLE_DIR/schema.graphql" > /dev/null

# Wait for schema to be active
echo "Waiting for schema creation..."
for i in {1..30}; do
    SCHEMA_STATUS=$($AWSCLI appsync get-schema-creation-status \
        --api-id "$API_ID" \
        --query "status" --output text 2>/dev/null || echo "PROCESSING")
    if [ "$SCHEMA_STATUS" = "ACTIVE" ] || [ "$SCHEMA_STATUS" = "SUCCESS" ]; then
        echo "Schema is active"
        break
    fi
    if [ "$SCHEMA_STATUS" = "FAILED" ]; then
        echo "Schema creation failed!"
        $AWSCLI appsync get-schema-creation-status --api-id "$API_ID"
        exit 1
    fi
    echo "Schema status: $SCHEMA_STATUS, waiting... ($i/30)"
    sleep 2
done

# Step 8: Create DynamoDB data source
echo "Creating DynamoDB data source..."
$AWSCLI appsync create-data-source \
    --api-id "$API_ID" \
    --name "ds_ddb" \
    --type "AMAZON_DYNAMODB" \
    --dynamodb-config "{\"tableName\": \"${TABLE_NAME}\", \"awsRegion\": \"us-east-1\"}" \
    --service-role-arn "$ROLE_ARN" > /dev/null

# Step 9: Create RDS data source
echo "Creating RDS data source..."
$AWSCLI appsync create-data-source \
    --api-id "$API_ID" \
    --name "ds_rds" \
    --type "RELATIONAL_DATABASE" \
    --relational-database-config "{
        \"relationalDatabaseSourceType\": \"RDS_HTTP_ENDPOINT\",
        \"rdsHttpEndpointConfig\": {
            \"awsRegion\": \"us-east-1\",
            \"dbClusterIdentifier\": \"${DB_CLUSTER_ARN}\",
            \"databaseName\": \"${DB_NAME}\",
            \"awsSecretStoreArn\": \"${SECRET_ARN}\"
        }
    }" \
    --service-role-arn "$ROLE_ARN" > /dev/null

# Step 10: Create resolvers with VTL templates
echo "Creating resolvers..."

create_resolver() {
    local type_name="$1"
    local field_name="$2"
    local data_source="$3"
    local request_template="$4"
    local response_template="$5"

    $AWSCLI appsync create-resolver \
        --api-id "$API_ID" \
        --type-name "$type_name" \
        --field-name "$field_name" \
        --data-source-name "$data_source" \
        --request-mapping-template "$(cat "$SAMPLE_DIR/templates/$request_template")" \
        --response-mapping-template "$(cat "$SAMPLE_DIR/templates/$response_template")" > /dev/null
}

# DynamoDB resolvers
create_resolver "Mutation" "addPostDDB" "ds_ddb" "ddb.PutItem.request.vlt" "ddb.PutItem.response.vlt"
create_resolver "Query" "getPostsDDB" "ds_ddb" "ddb.Scan.request.vlt" "ddb.Scan.response.vlt"

# RDS resolvers
create_resolver "Mutation" "addPostRDS" "ds_rds" "rds.insert.request.vlt" "rds.insert.response.vlt"
create_resolver "Query" "getPostsRDS" "ds_rds" "rds.select.request.vlt" "rds.select.response.vlt"

# Save configuration
cat > "$SCRIPT_DIR/.env" << EOF
API_ID=$API_ID
API_URL=$API_URL
API_KEY=$API_KEY
API_NAME=$API_NAME
TABLE_NAME=$TABLE_NAME
DB_CLUSTER_ID=$DB_CLUSTER_ID
DB_CLUSTER_ARN=$DB_CLUSTER_ARN
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
SECRET_NAME=$SECRET_NAME
SECRET_ARN=$SECRET_ARN
ROLE_NAME=$ROLE_NAME
ROLE_ARN=$ROLE_ARN
EOF

echo ""
echo "Deployment complete!"
echo "API ID: ${API_ID}"
echo "API URL: ${API_URL}"
echo "API Key: ${API_KEY}"
echo "Table: ${TABLE_NAME}"
echo "RDS Cluster: ${DB_CLUSTER_ID}"
