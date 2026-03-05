#!/bin/bash
set -euo pipefail

# =============================================================================
# Step Functions Lambda - Deployment Script (Python)
#
# Demonstrates AWS Step Functions orchestrating multiple Lambda functions
# in a parallel workflow pattern.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"

# Configuration
PREFIX="local"
SUFFIX="$(date +%s)"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID="000000000000"

# Function names
ADAM_FUNCTION="${PREFIX}-sfn-adam-${SUFFIX}"
COLE_FUNCTION="${PREFIX}-sfn-cole-${SUFFIX}"
COMBINE_FUNCTION="${PREFIX}-sfn-combine-${SUFFIX}"
STATE_MACHINE_NAME="${PREFIX}-parallel-workflow-${SUFFIX}"

# Determine CLI to use
if command -v awslocal &> /dev/null; then
    AWS="awslocal"
else
    AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"
fi

echo "Deploying Step Functions Lambda Sample"
echo "  State Machine: $STATE_MACHINE_NAME"
echo "  Region: $REGION"

# Create IAM roles
echo ""
echo "Step 1: Creating IAM roles..."

# Lambda execution role
LAMBDA_ROLE_NAME="${PREFIX}-lambda-role-${SUFFIX}"
LAMBDA_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$LAMBDA_ROLE_NAME"

$AWS iam create-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }' \
    --region "$REGION" > /dev/null 2>&1 || true

# Step Functions execution role
SFN_ROLE_NAME="${PREFIX}-sfn-role-${SUFFIX}"
SFN_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$SFN_ROLE_NAME"

$AWS iam create-role \
    --role-name "$SFN_ROLE_NAME" \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "states.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }' \
    --region "$REGION" > /dev/null 2>&1 || true

# Package Lambda functions
echo "Step 2: Packaging Lambda functions..."
PACKAGE_DIR=$(mktemp -d)

# Package Adam function
cp "$SRC_DIR/lambda_adam.py" "$PACKAGE_DIR/handler.py"
cd "$PACKAGE_DIR"
zip -q adam.zip handler.py
rm handler.py

# Package Cole function
cp "$SRC_DIR/lambda_cole.py" "$PACKAGE_DIR/handler.py"
zip -q cole.zip handler.py
rm handler.py

# Package Combine function
cp "$SRC_DIR/lambda_combine.py" "$PACKAGE_DIR/handler.py"
zip -q combine.zip handler.py
rm handler.py
cd - > /dev/null

# Create Lambda functions
echo "Step 3: Creating Lambda functions..."

# Adam function
$AWS lambda create-function \
    --function-name "$ADAM_FUNCTION" \
    --runtime python3.12 \
    --handler handler.handler \
    --role "$LAMBDA_ROLE_ARN" \
    --zip-file "fileb://$PACKAGE_DIR/adam.zip" \
    --region "$REGION" > /dev/null

ADAM_ARN=$($AWS lambda get-function \
    --function-name "$ADAM_FUNCTION" \
    --query 'Configuration.FunctionArn' \
    --output text \
    --region "$REGION")
echo "  Adam: $ADAM_ARN"

# Cole function
$AWS lambda create-function \
    --function-name "$COLE_FUNCTION" \
    --runtime python3.12 \
    --handler handler.handler \
    --role "$LAMBDA_ROLE_ARN" \
    --zip-file "fileb://$PACKAGE_DIR/cole.zip" \
    --region "$REGION" > /dev/null

COLE_ARN=$($AWS lambda get-function \
    --function-name "$COLE_FUNCTION" \
    --query 'Configuration.FunctionArn' \
    --output text \
    --region "$REGION")
echo "  Cole: $COLE_ARN"

# Combine function
$AWS lambda create-function \
    --function-name "$COMBINE_FUNCTION" \
    --runtime python3.12 \
    --handler handler.handler \
    --role "$LAMBDA_ROLE_ARN" \
    --zip-file "fileb://$PACKAGE_DIR/combine.zip" \
    --region "$REGION" > /dev/null

COMBINE_ARN=$($AWS lambda get-function \
    --function-name "$COMBINE_FUNCTION" \
    --query 'Configuration.FunctionArn' \
    --output text \
    --region "$REGION")
echo "  Combine: $COMBINE_ARN"

# Create State Machine
echo "Step 4: Creating Step Functions state machine..."

# Replace placeholders in state machine definition
STATE_MACHINE_DEF=$(cat "$SRC_DIR/state-machine.json" | \
    sed "s|\${ADAM_FUNCTION_ARN}|$ADAM_ARN|g" | \
    sed "s|\${COLE_FUNCTION_ARN}|$COLE_ARN|g" | \
    sed "s|\${COMBINE_FUNCTION_ARN}|$COMBINE_ARN|g")

STATE_MACHINE_ARN=$($AWS stepfunctions create-state-machine \
    --name "$STATE_MACHINE_NAME" \
    --definition "$STATE_MACHINE_DEF" \
    --role-arn "$SFN_ROLE_ARN" \
    --query 'stateMachineArn' \
    --output text \
    --region "$REGION")

echo "  State Machine ARN: $STATE_MACHINE_ARN"

# Save config for test script
cat > "$SCRIPT_DIR/.env" << EOF
PREFIX=$PREFIX
SUFFIX=$SUFFIX
REGION=$REGION
ACCOUNT_ID=$ACCOUNT_ID
ADAM_FUNCTION=$ADAM_FUNCTION
ADAM_ARN=$ADAM_ARN
COLE_FUNCTION=$COLE_FUNCTION
COLE_ARN=$COLE_ARN
COMBINE_FUNCTION=$COMBINE_FUNCTION
COMBINE_ARN=$COMBINE_ARN
STATE_MACHINE_NAME=$STATE_MACHINE_NAME
STATE_MACHINE_ARN=$STATE_MACHINE_ARN
LAMBDA_ROLE_NAME=$LAMBDA_ROLE_NAME
SFN_ROLE_NAME=$SFN_ROLE_NAME
EOF

# Cleanup
rm -rf "$PACKAGE_DIR"

echo ""
echo "Deployment complete!"
echo "  State Machine: $STATE_MACHINE_NAME"
echo "  Adam Function: $ADAM_FUNCTION"
echo "  Cole Function: $COLE_FUNCTION"
echo "  Combine Function: $COMBINE_FUNCTION"
