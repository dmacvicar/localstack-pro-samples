#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR/.."

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

JAR_S3_KEY="code/java-spark/java-demo-1.0.jar"

echo "=== Deploying EMR Serverless Spark (CDK) ==="

# Build JAR if needed
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

cd "$SCRIPT_DIR"

uv pip install -r requirements.txt 2>/dev/null || pip install -r requirements.txt
$CDK bootstrap 2>/dev/null || true
$CDK deploy --require-approval never --outputs-file cdk-outputs.json

STACK_OUTPUT=$(cat cdk-outputs.json | jq -r '.EmrServerlessSparkStack')

APP_NAME=$(echo "$STACK_OUTPUT" | jq -r '.AppName')
APP_ID=$(echo "$STACK_OUTPUT" | jq -r '.AppId')
S3_BUCKET=$(echo "$STACK_OUTPUT" | jq -r '.S3Bucket')
JOB_ROLE_ARN=$(echo "$STACK_OUTPUT" | jq -r '.JobRoleArn')

# Upload JAR
echo "Uploading JAR to S3..."
$AWSCLI s3 cp "$JAR_PATH" "s3://${S3_BUCKET}/${JAR_S3_KEY}"

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
    --job-driver "{\"sparkSubmit\": {\"entryPoint\": \"s3://${S3_BUCKET}/${JAR_S3_KEY}\", \"sparkSubmitParameters\": \"--class HelloWorld\"}}" \
    --configuration-overrides "{\"monitoringConfiguration\": {\"s3MonitoringConfiguration\": {\"logUri\": \"s3://${S3_BUCKET}/logs/\"}}}" \
    --query "jobRunId" --output text)

echo "Waiting for job to complete..."
for i in {1..60}; do
    JOB_STATE=$($AWSCLI emr-serverless get-job-run \
        --application-id "$APP_ID" --job-run-id "$JOB_RUN_ID" \
        --query "jobRun.state" --output text 2>/dev/null || echo "SUBMITTED")
    [ "$JOB_STATE" = "SUCCESS" ] || [ "$JOB_STATE" = "FAILED" ] || [ "$JOB_STATE" = "CANCELLED" ] && break
    sleep 3
done

cat > "$SCRIPT_DIR/../scripts/.env" << EOF
APP_NAME=$APP_NAME
APP_ID=$APP_ID
S3_BUCKET=$S3_BUCKET
JOB_ROLE_ARN=$JOB_ROLE_ARN
JOB_RUN_ID=$JOB_RUN_ID
JAR_S3_KEY=$JAR_S3_KEY
EOF

echo "Deployment complete!"
