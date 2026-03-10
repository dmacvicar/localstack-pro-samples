#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="GlueEtlJobsStack"

echo "Deploying Glue ETL Jobs with CDK..."

cd "$SCRIPT_DIR"

# Install CDK dependencies
pip install -q -r requirements.txt

# Bootstrap CDK (if needed)
cdklocal bootstrap --quiet 2>/dev/null || true

# Deploy
cdklocal deploy "$STACK_NAME" --require-approval never --outputs-file outputs.json

# Extract outputs
CLUSTER_IDENTIFIER=$(jq -r ".\"$STACK_NAME\".ClusterIdentifier" outputs.json)
DB_PORT=$(jq -r ".\"$STACK_NAME\".ClusterPort" outputs.json)
CONNECTION_NAME=$(jq -r ".\"$STACK_NAME\".ConnectionName" outputs.json)
JOB_NAME=$(jq -r ".\"$STACK_NAME\".JobName" outputs.json)
BUCKET=$(jq -r ".\"$STACK_NAME\".ScriptBucketName" outputs.json)
TARGET_BUCKET=$(jq -r ".\"$STACK_NAME\".TargetBucketName" outputs.json)
SECRET_ARN=$(jq -r ".\"$STACK_NAME\".SecretArn" outputs.json)

# Upload job script to S3
echo "Uploading PySpark job script to S3..."
awslocal s3 cp "$SAMPLE_DIR/src/job.py" "s3://$BUCKET/job.py"

# Populate database tables with test data
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

# Start Glue job
echo "Starting Glue job run..."
RUN_ID=$(awslocal glue start-job-run --job-name "$JOB_NAME" | jq -r '.JobRunId')

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

# Write environment variables
mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" << EOF
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
