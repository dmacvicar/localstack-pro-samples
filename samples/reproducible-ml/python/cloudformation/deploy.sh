#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR/.."

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

STACK_NAME="reproducible-ml"
BUCKET_NAME="reproducible-ml-cfn"

echo "=== Deploying Reproducible ML (CloudFormation) ==="

# Create bucket and upload code before stack (Lambda Code references S3)
$AWSCLI s3 mb "s3://${BUCKET_NAME}" 2>/dev/null || true

# Zip and upload Lambda functions
cd "$SAMPLE_DIR"
zip -j /tmp/ml-train.zip train.py
zip -j /tmp/ml-infer.zip infer.py
$AWSCLI s3 cp /tmp/ml-train.zip "s3://${BUCKET_NAME}/ml-train.zip"
$AWSCLI s3 cp /tmp/ml-infer.zip "s3://${BUCKET_NAME}/ml-infer.zip"

# Upload data files
$AWSCLI s3 cp "$SAMPLE_DIR/data/digits.csv.gz" "s3://${BUCKET_NAME}/digits.csv.gz"
$AWSCLI s3 cp "$SAMPLE_DIR/data/digits.rst" "s3://${BUCKET_NAME}/digits.rst"

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
TRAIN_FUNCTION=$(get_output TrainFunction)
PREDICT_FUNCTION=$(get_output PredictFunction)

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
STACK_NAME=$STACK_NAME
EOF

echo "Deployment complete!"
