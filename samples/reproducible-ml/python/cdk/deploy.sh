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

BUCKET_NAME="reproducible-ml-cdk"

echo "=== Deploying Reproducible ML (CDK) ==="

# Create bucket and upload code before CDK deploy (Lambda Code references S3)
$AWSCLI s3 mb "s3://${BUCKET_NAME}" 2>/dev/null || true

cd "$SAMPLE_DIR"
zip -j /tmp/ml-train.zip train.py
zip -j /tmp/ml-infer.zip infer.py
$AWSCLI s3 cp /tmp/ml-train.zip "s3://${BUCKET_NAME}/ml-train.zip"
$AWSCLI s3 cp /tmp/ml-infer.zip "s3://${BUCKET_NAME}/ml-infer.zip"
$AWSCLI s3 cp "$SAMPLE_DIR/data/digits.csv.gz" "s3://${BUCKET_NAME}/digits.csv.gz"
$AWSCLI s3 cp "$SAMPLE_DIR/data/digits.rst" "s3://${BUCKET_NAME}/digits.rst"

cd "$SCRIPT_DIR"

uv pip install -r requirements.txt 2>/dev/null || pip install -r requirements.txt
$CDK bootstrap 2>/dev/null || true
$CDK deploy --require-approval never --outputs-file cdk-outputs.json

STACK_OUTPUT=$(cat cdk-outputs.json | jq -r '.ReproducibleMlStack')

S3_BUCKET=$(echo "$STACK_OUTPUT" | jq -r '.S3Bucket')
TRAIN_FUNCTION=$(echo "$STACK_OUTPUT" | jq -r '.TrainFunctionOutput')
PREDICT_FUNCTION=$(echo "$STACK_OUTPUT" | jq -r '.PredictFunctionOutput')

# Wait for functions
$AWSCLI lambda wait function-active-v2 --function-name "$TRAIN_FUNCTION" 2>/dev/null || sleep 5
$AWSCLI lambda wait function-active-v2 --function-name "$PREDICT_FUNCTION" 2>/dev/null || sleep 5

# Invoke training
echo "Invoking training function..."
$AWSCLI lambda invoke \
    --function-name "$TRAIN_FUNCTION" \
    /tmp/ml-train-result.json > /dev/null
echo "Training result: $(cat /tmp/ml-train-result.json)"

# Invoke prediction
echo "Invoking prediction function..."
$AWSCLI lambda invoke \
    --function-name "$PREDICT_FUNCTION" \
    /tmp/ml-predict-result.json > /dev/null
echo "Prediction result: $(cat /tmp/ml-predict-result.json)"

cat > "$SCRIPT_DIR/../scripts/.env" << EOF
S3_BUCKET=$S3_BUCKET
TRAIN_FUNCTION=$TRAIN_FUNCTION
PREDICT_FUNCTION=$PREDICT_FUNCTION
EOF

echo "Deployment complete!"
