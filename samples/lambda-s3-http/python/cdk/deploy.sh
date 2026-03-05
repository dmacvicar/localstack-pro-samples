#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="LambdaS3HttpStack"

echo "Deploying Lambda S3 HTTP via CDK"

cd "$SCRIPT_DIR"

if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

echo "Step 1: Installing CDK dependencies..."
uv pip install --system -r requirements.txt --quiet 2>/dev/null || true

echo "Step 2: Bootstrapping CDK..."
$CDK bootstrap --quiet 2>/dev/null || true

echo "Step 3: Deploying CDK stack..."
$CDK deploy --require-approval never --outputs-file cdk-outputs.json

echo "Step 4: Extracting outputs..."
TABLE_NAME=$(jq -r ".$STACK_NAME.TableNameOutput" cdk-outputs.json)
BUCKET_NAME=$(jq -r ".$STACK_NAME.BucketNameOutput" cdk-outputs.json)
QUEUE_NAME=$(jq -r ".$STACK_NAME.QueueNameOutput" cdk-outputs.json)
QUEUE_URL=$(jq -r ".$STACK_NAME.QueueUrlOutput" cdk-outputs.json)
HTTP_FUNCTION=$(jq -r ".$STACK_NAME.HttpFunctionOutput" cdk-outputs.json)
S3_FUNCTION=$(jq -r ".$STACK_NAME.S3FunctionOutput" cdk-outputs.json)
SQS_FUNCTION=$(jq -r ".$STACK_NAME.SqsFunctionOutput" cdk-outputs.json)

cat > "$SCRIPT_DIR/../scripts/.env" << EOF
TABLE_NAME=$TABLE_NAME
BUCKET_NAME=$BUCKET_NAME
QUEUE_NAME=$QUEUE_NAME
QUEUE_URL=$QUEUE_URL
HTTP_FUNCTION=$HTTP_FUNCTION
S3_FUNCTION=$S3_FUNCTION
SQS_FUNCTION=$SQS_FUNCTION
REGION=us-east-1
EOF

echo ""
echo "Deployment complete!"
echo "  Table: $TABLE_NAME"
echo "  Bucket: $BUCKET_NAME"
echo "  Queue: $QUEUE_NAME"
echo "  HTTP Function: $HTTP_FUNCTION"
echo "  S3 Function: $S3_FUNCTION"
echo "  SQS Function: $SQS_FUNCTION"
