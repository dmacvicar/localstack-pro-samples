#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    TF="terraform"
fi

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

echo "=== Deploying SageMaker Inference (Terraform) ==="

cd "$SCRIPT_DIR"

$TF init -input=false
$TF apply -auto-approve -input=false

S3_BUCKET=$($TF output -raw s3_bucket)
MODEL_NAME=$($TF output -raw model_name)
CONFIG_NAME=$($TF output -raw config_name)
ENDPOINT_NAME=$($TF output -raw endpoint_name)

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
