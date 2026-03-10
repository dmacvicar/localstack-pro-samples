#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"

BUCKET="glue-pyspark-test"
TARGET_BUCKET="glue-sample-target"
JOB_NAME="test-job1"
S3_URL="s3://$BUCKET/job.py"
CLUSTER_IDENTIFIER="glue-etl-cluster1"
CONNECTION_NAME="glue-etl-cluster1-connection"

echo "Putting PySpark script to test S3 bucket..."
awslocal s3 mb "s3://$BUCKET"
awslocal s3 cp "$SAMPLE_DIR/src/job.py" "$S3_URL"
awslocal s3 mb "s3://$TARGET_BUCKET"

echo "Creating RDS Aurora PostgreSQL cluster..."
awslocal rds create-db-cluster \
    --db-cluster-identifier "$CLUSTER_IDENTIFIER" \
    --engine aurora-postgresql \
    --database-name test > /dev/null

echo "Waiting for RDS cluster to be available..."
for i in {1..60}; do
    STATUS=$(awslocal rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_IDENTIFIER" \
        --query "DBClusters[0].Status" \
        --output text 2>/dev/null || echo "creating")
    if [ "$STATUS" = "available" ]; then
        echo "RDS cluster is available"
        break
    fi
    echo "Status: $STATUS, waiting... ($i/60)"
    sleep 5
done

if [ "$STATUS" != "available" ]; then
    echo "RDS cluster did not become available in time"
    exit 1
fi

DB_PORT=$(awslocal rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_IDENTIFIER" \
    | jq -r '.DBClusters[0].Port')
echo "Using local RDS database on port $DB_PORT"

echo "Creating Glue databases and tables..."
awslocal glue create-database --database-input '{"Name": "legislators"}'
awslocal glue create-table --database legislators \
    --table-input '{"Name": "memberships_json", "Parameters": {"connectionName": "'"$CONNECTION_NAME"'"}, "StorageDescriptor": {"Location": "test.memberships"}}'
awslocal glue create-table --database legislators \
    --table-input '{"Name": "persons_json", "Parameters": {"connectionName": "'"$CONNECTION_NAME"'"}, "StorageDescriptor": {"Location": "test.persons"}}'
awslocal glue create-table --database legislators \
    --table-input '{"Name": "organizations_json", "Parameters": {"connectionName": "'"$CONNECTION_NAME"'"}, "StorageDescriptor": {"Location": "test.organizations"}}'
awslocal glue create-connection \
    --connection-input '{"Name": "'"$CONNECTION_NAME"'", "ConnectionType": "JDBC", "ConnectionProperties": {"USERNAME": "test", "PASSWORD": "test", "JDBC_CONNECTION_URL": "jdbc:postgresql://localhost.localstack.cloud:'"$DB_PORT"'"}}'

SECRET_ARN=$(awslocal secretsmanager create-secret --name pass --secret-string "test" | jq -r ".ARN")

echo "Creating Postgres database tables with data..."
RESOURCE_ARN="arn:aws:rds:us-east-1:000000000000:cluster:$CLUSTER_IDENTIFIER"

awslocal rds-data execute-statement --resource-arn "$RESOURCE_ARN" --secret-arn "$SECRET_ARN" \
    --sql 'CREATE TABLE IF NOT EXISTS persons(id varchar, name varchar)'
awslocal rds-data execute-statement --resource-arn "$RESOURCE_ARN" --secret-arn "$SECRET_ARN" \
    --sql 'CREATE TABLE IF NOT EXISTS organizations(org_id varchar, org_name varchar)'
awslocal rds-data execute-statement --resource-arn "$RESOURCE_ARN" --secret-arn "$SECRET_ARN" \
    --sql 'CREATE TABLE IF NOT EXISTS memberships(person_id varchar, organization_id varchar)'
awslocal rds-data execute-statement --resource-arn "$RESOURCE_ARN" --secret-arn "$SECRET_ARN" \
    --sql "INSERT INTO persons(id, name) VALUES('p1', 'person 1')"
awslocal rds-data execute-statement --resource-arn "$RESOURCE_ARN" --secret-arn "$SECRET_ARN" \
    --sql "INSERT INTO organizations(org_id, org_name) VALUES('o1', 'org1')"
awslocal rds-data execute-statement --resource-arn "$RESOURCE_ARN" --secret-arn "$SECRET_ARN" \
    --sql "INSERT INTO memberships(person_id, organization_id) VALUES('p1', 'o1')"
awslocal rds-data execute-statement --resource-arn "$RESOURCE_ARN" --secret-arn "$SECRET_ARN" \
    --sql 'CREATE TABLE IF NOT EXISTS hist_root(id varchar, name varchar, org_id varchar, org_name varchar, person_id varchar, organization_id varchar)'

echo "Starting Glue job from PySpark script..."
awslocal glue create-job --name "$JOB_NAME" --role r1 \
    --command '{"Name": "pythonshell", "ScriptLocation": "'"$S3_URL"'"}' \
    --connections '{"Connections": ["'"$CLUSTER_IDENTIFIER"'"]}'

RUN_ID=$(awslocal glue start-job-run --job-name "$JOB_NAME" | jq -r .JobRunId)

echo "Waiting for Glue job to complete (Spark init may take several minutes)..."
STATE=""
for i in {1..60}; do
    STATE=$(awslocal glue get-job-run --job-name "$JOB_NAME" --run-id "$RUN_ID" | jq -r '.JobRun.JobRunState')
    echo "Job state: $STATE ($i/60)"
    if [ "$STATE" = "SUCCEEDED" ]; then
        echo "Glue job completed successfully!"
        break
    elif [ "$STATE" = "FAILED" ]; then
        echo "Glue job failed!"
        awslocal glue get-job-run --job-name "$JOB_NAME" --run-id "$RUN_ID" | jq '.JobRun.ErrorMessage'
        exit 1
    fi
    sleep 10
done

if [ "$STATE" != "SUCCEEDED" ]; then
    echo "Glue job did not complete in time (last state: $STATE)"
    exit 1
fi

# Save configuration for tests
cat > "$SCRIPT_DIR/.env" << EOF
BUCKET=$BUCKET
TARGET_BUCKET=$TARGET_BUCKET
JOB_NAME=$JOB_NAME
JOB_RUN_ID=$RUN_ID
CLUSTER_IDENTIFIER=$CLUSTER_IDENTIFIER
CONNECTION_NAME=$CONNECTION_NAME
DB_PORT=$DB_PORT
SECRET_ARN=$SECRET_ARN
EOF

echo ""
echo "Deployment complete!"
echo "Job Name: $JOB_NAME"
echo "Run ID: $RUN_ID"
