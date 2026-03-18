#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR/.."

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

APP_NAME="serverless-java-demo-scripts"
BUCKET_NAME="emr-spark-scripts"
ROLE_NAME="emr-serverless-role-scripts"
JAR_S3_KEY="code/java-spark/java-demo-1.0.jar"

echo "=== Deploying EMR Serverless Spark (Scripts) ==="

# Build JAR if Maven is available, otherwise use pre-built
JAR_PATH="$SAMPLE_DIR/hello-world/target/java-demo-1.0.jar"
if [ ! -f "$JAR_PATH" ]; then
    if command -v mvn &> /dev/null; then
        echo "Building JAR with Maven..."
        cd "$SAMPLE_DIR/hello-world"
        mvn package -q -DskipTests
        cd "$SCRIPT_DIR"
    else
        echo "Maven not found and no pre-built JAR at $JAR_PATH"
        exit 1
    fi
fi

# Create S3 bucket
$AWSCLI s3 mb "s3://${BUCKET_NAME}" 2>/dev/null || true

# Upload JAR
echo "Uploading JAR to S3..."
$AWSCLI s3 cp "$JAR_PATH" "s3://${BUCKET_NAME}/${JAR_S3_KEY}"

# Create IAM role
JOB_ROLE_ARN=$($AWSCLI iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "emr-serverless.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }' \
    --query "Role.Arn" --output text 2>/dev/null || \
    $AWSCLI iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text)

# Create EMR Serverless application
APP_ID=$($AWSCLI emr-serverless create-application \
    --type SPARK \
    --name "$APP_NAME" \
    --release-label "emr-6.9.0" \
    --query "applicationId" --output text)

# Start application
echo "Starting application..."
$AWSCLI emr-serverless start-application --application-id "$APP_ID"

for i in {1..30}; do
    STATE=$($AWSCLI emr-serverless get-application \
        --application-id "$APP_ID" \
        --query "application.state" --output text 2>/dev/null || echo "CREATING")
    [ "$STATE" = "STARTED" ] && break
    sleep 2
done

# Submit job
echo "Submitting Spark job..."
JOB_RUN_ID=$($AWSCLI emr-serverless start-job-run \
    --application-id "$APP_ID" \
    --execution-role-arn "$JOB_ROLE_ARN" \
    --job-driver "{\"sparkSubmit\": {\"entryPoint\": \"s3://${BUCKET_NAME}/${JAR_S3_KEY}\", \"sparkSubmitParameters\": \"--class HelloWorld\"}}" \
    --configuration-overrides "{\"monitoringConfiguration\": {\"s3MonitoringConfiguration\": {\"logUri\": \"s3://${BUCKET_NAME}/logs/\"}}}" \
    --query "jobRunId" --output text)

echo "Waiting for job to complete..."
for i in {1..60}; do
    JOB_STATE=$($AWSCLI emr-serverless get-job-run \
        --application-id "$APP_ID" --job-run-id "$JOB_RUN_ID" \
        --query "jobRun.state" --output text 2>/dev/null || echo "SUBMITTED")
    [ "$JOB_STATE" = "SUCCESS" ] || [ "$JOB_STATE" = "FAILED" ] || [ "$JOB_STATE" = "CANCELLED" ] && break
    sleep 3
done

cat > "$SCRIPT_DIR/.env" << EOF
APP_NAME=$APP_NAME
APP_ID=$APP_ID
S3_BUCKET=$BUCKET_NAME
JOB_ROLE_ARN=$JOB_ROLE_ARN
JOB_RUN_ID=$JOB_RUN_ID
JAR_S3_KEY=$JAR_S3_KEY
EOF

echo "Deployment complete!"
