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

BUCKET_NAME="sagemaker-models-cdk"

echo "=== Deploying SageMaker Inference (CDK) ==="

# Upload model before CDK deploy (model references S3)
$AWSCLI s3 mb "s3://${BUCKET_NAME}" 2>/dev/null || true
$AWSCLI s3 cp "$SAMPLE_DIR/data/model.tar.gz" "s3://${BUCKET_NAME}/model.tar.gz"

cd "$SCRIPT_DIR"

uv pip install -r requirements.txt 2>/dev/null || pip install -r requirements.txt
$CDK bootstrap 2>/dev/null || true
$CDK deploy --require-approval never --outputs-file cdk-outputs.json

STACK_OUTPUT=$(cat cdk-outputs.json | jq -r '.SagemakerInferenceStack')

S3_BUCKET=$(echo "$STACK_OUTPUT" | jq -r '.S3Bucket')
MODEL_NAME=$(echo "$STACK_OUTPUT" | jq -r '.ModelName')
CONFIG_NAME=$(echo "$STACK_OUTPUT" | jq -r '.ConfigName')
ENDPOINT_NAME=$(echo "$STACK_OUTPUT" | jq -r '.EndpointNameOutput')

# Wait for endpoint
echo "Waiting for endpoint..."
for i in {1..30}; do
    STATUS=$($AWSCLI sagemaker describe-endpoint \
        --endpoint-name "$ENDPOINT_NAME" \
        --query "EndpointStatus" --output text 2>/dev/null || echo "Creating")
    echo "  Status: $STATUS"
    [ "$STATUS" = "InService" ] && break
    [ "$STATUS" = "Failed" ] && echo "Endpoint failed!" && break
    sleep 5
done

cat > "$SCRIPT_DIR/../scripts/.env" << EOF
S3_BUCKET=$S3_BUCKET
MODEL_NAME=$MODEL_NAME
CONFIG_NAME=$CONFIG_NAME
ENDPOINT_NAME=$ENDPOINT_NAME
EOF

echo "Deployment complete!"
