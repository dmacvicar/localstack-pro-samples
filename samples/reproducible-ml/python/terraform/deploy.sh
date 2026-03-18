#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR/.."

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

echo "=== Deploying Reproducible ML (Terraform) ==="

# Zip Lambda functions
cd "$SAMPLE_DIR"
zip -j "$SCRIPT_DIR/train.zip" train.py
zip -j "$SCRIPT_DIR/infer.zip" infer.py

cd "$SCRIPT_DIR"

$TF init -input=false
$TF apply -auto-approve -input=false

S3_BUCKET=$($TF output -raw s3_bucket)
TRAIN_FUNCTION=$($TF output -raw train_function)
PREDICT_FUNCTION=$($TF output -raw predict_function)

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
