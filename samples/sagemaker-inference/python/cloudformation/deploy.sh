#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR/.."

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

STACK_NAME="sagemaker-inference"
BUCKET_NAME="sagemaker-models-cfn"

echo "=== Deploying SageMaker Inference (CloudFormation) ==="

# Create bucket and upload model before stack (Model references S3)
$AWSCLI s3 mb "s3://${BUCKET_NAME}" 2>/dev/null || true
$AWSCLI s3 cp "$SAMPLE_DIR/data/model.tar.gz" "s3://${BUCKET_NAME}/model.tar.gz"

cd "$SCRIPT_DIR"

$AWSCLI cloudformation deploy \
    --template-file template.yml \
    --stack-name "$STACK_NAME" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

$AWSCLI cloudformation wait stack-create-complete --stack-name "$STACK_NAME" 2>/dev/null || true

get_output() {
    $AWSCLI cloudformation describe-stacks --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

S3_BUCKET=$(get_output S3Bucket)
MODEL_NAME=$(get_output ModelName)
CONFIG_NAME=$(get_output ConfigName)
ENDPOINT_NAME=$(get_output EndpointName)

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
STACK_NAME=$STACK_NAME
EOF

echo "Deployment complete!"
