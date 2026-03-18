#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR/.."

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

BUCKET_NAME="sagemaker-models-scripts"
MODEL_NAME="sample-scripts"
CONFIG_NAME="sample-cf-scripts"
ENDPOINT_NAME="sample-ep-scripts"
CONTAINER_IMAGE="763104351884.dkr.ecr.us-east-1.amazonaws.com/pytorch-inference:1.5.0-cpu-py3"
EXECUTION_ROLE_ARN="arn:aws:iam::000000000000:role/sagemaker-role"

echo "=== Deploying SageMaker Inference (Scripts) ==="

# Create S3 bucket and upload model
$AWSCLI s3 mb "s3://${BUCKET_NAME}" 2>/dev/null || true
echo "Uploading model..."
$AWSCLI s3 cp "$SAMPLE_DIR/data/model.tar.gz" "s3://${BUCKET_NAME}/model.tar.gz"

# Create SageMaker model
echo "Creating SageMaker model..."
$AWSCLI sagemaker create-model \
    --model-name "$MODEL_NAME" \
    --execution-role-arn "$EXECUTION_ROLE_ARN" \
    --primary-container "{\"Image\": \"${CONTAINER_IMAGE}\", \"ModelDataUrl\": \"s3://${BUCKET_NAME}/model.tar.gz\"}"

# Create endpoint configuration
echo "Creating endpoint configuration..."
$AWSCLI sagemaker create-endpoint-config \
    --endpoint-config-name "$CONFIG_NAME" \
    --production-variants "[{\"VariantName\": \"var-1\", \"ModelName\": \"${MODEL_NAME}\", \"InitialInstanceCount\": 1, \"InstanceType\": \"ml.m5.large\"}]"

# Create endpoint
echo "Creating endpoint..."
$AWSCLI sagemaker create-endpoint \
    --endpoint-name "$ENDPOINT_NAME" \
    --endpoint-config-name "$CONFIG_NAME"

# Wait for endpoint to be InService
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

cat > "$SCRIPT_DIR/.env" << EOF
S3_BUCKET=$BUCKET_NAME
MODEL_NAME=$MODEL_NAME
CONFIG_NAME=$CONFIG_NAME
ENDPOINT_NAME=$ENDPOINT_NAME
CONTAINER_IMAGE=$CONTAINER_IMAGE
EOF

echo "Deployment complete!"
