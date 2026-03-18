#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR/.."

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

BUCKET_NAME="reproducible-ml-scripts"
TRAIN_FUNCTION="ml-train-scripts"
PREDICT_FUNCTION="ml-predict-scripts"
SKLEARN_LAYER="arn:aws:lambda:us-east-1:446751924810:layer:python-3-8-scikit-learn-0-22-0:3"

echo "=== Deploying Reproducible ML (Scripts) ==="

# Create S3 bucket
$AWSCLI s3 mb "s3://${BUCKET_NAME}" 2>/dev/null || true

# Upload data files
echo "Uploading data files..."
$AWSCLI s3 cp "$SAMPLE_DIR/data/digits.csv.gz" "s3://${BUCKET_NAME}/digits.csv.gz"
$AWSCLI s3 cp "$SAMPLE_DIR/data/digits.rst" "s3://${BUCKET_NAME}/digits.rst"

# Zip Lambda functions
cd "$SAMPLE_DIR"
zip -j /tmp/ml-train.zip train.py
zip -j /tmp/ml-infer.zip infer.py

# Upload Lambda code to S3
$AWSCLI s3 cp /tmp/ml-train.zip "s3://${BUCKET_NAME}/ml-train.zip"
$AWSCLI s3 cp /tmp/ml-infer.zip "s3://${BUCKET_NAME}/ml-infer.zip"

# Create training Lambda
echo "Creating training Lambda..."
$AWSCLI lambda create-function \
    --function-name "$TRAIN_FUNCTION" \
    --runtime python3.8 \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --handler train.handler \
    --timeout 600 \
    --code "{\"S3Bucket\":\"${BUCKET_NAME}\",\"S3Key\":\"ml-train.zip\"}" \
    --layers "$SKLEARN_LAYER" \
    --environment "Variables={S3_BUCKET=${BUCKET_NAME}}" \
    --output text --query 'FunctionArn' > /dev/null

# Create prediction Lambda
echo "Creating prediction Lambda..."
$AWSCLI lambda create-function \
    --function-name "$PREDICT_FUNCTION" \
    --runtime python3.8 \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --handler infer.handler \
    --timeout 600 \
    --code "{\"S3Bucket\":\"${BUCKET_NAME}\",\"S3Key\":\"ml-infer.zip\"}" \
    --layers "$SKLEARN_LAYER" \
    --environment "Variables={S3_BUCKET=${BUCKET_NAME}}" \
    --output text --query 'FunctionArn' > /dev/null

# Wait for functions to be active
echo "Waiting for functions..."
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

cat > "$SCRIPT_DIR/.env" << EOF
S3_BUCKET=$BUCKET_NAME
TRAIN_FUNCTION=$TRAIN_FUNCTION
PREDICT_FUNCTION=$PREDICT_FUNCTION
EOF

echo "Deployment complete!"
