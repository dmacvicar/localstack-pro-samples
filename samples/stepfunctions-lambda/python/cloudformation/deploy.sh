#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="stepfunctions-lambda-stack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Step Functions Lambda via CloudFormation"

# Use aws CLI directly with endpoint-url to avoid awslocal --s3-endpoint-url bug
AWS="aws --endpoint-url=http://localhost:4566"

cd "$SCRIPT_DIR"

echo "Step 1: Deploying CloudFormation stack..."
$AWS cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file template.yml \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --no-fail-on-empty-changeset

echo "Step 2: Extracting outputs..."
OUTPUTS=$($AWS cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs' --region "$REGION")

ADAM_FUNCTION=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="AdamFunction") | .OutputValue')
ADAM_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="AdamArn") | .OutputValue')
COLE_FUNCTION=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="ColeFunction") | .OutputValue')
COLE_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="ColeArn") | .OutputValue')
COMBINE_FUNCTION=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="CombineFunction") | .OutputValue')
COMBINE_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="CombineArn") | .OutputValue')
STATE_MACHINE_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="StateMachineName") | .OutputValue')
STATE_MACHINE_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="StateMachineArn") | .OutputValue')

cat > "$SCRIPT_DIR/../scripts/.env" << EOF
ADAM_FUNCTION=$ADAM_FUNCTION
ADAM_ARN=$ADAM_ARN
COLE_FUNCTION=$COLE_FUNCTION
COLE_ARN=$COLE_ARN
COMBINE_FUNCTION=$COMBINE_FUNCTION
COMBINE_ARN=$COMBINE_ARN
STATE_MACHINE_NAME=$STATE_MACHINE_NAME
STATE_MACHINE_ARN=$STATE_MACHINE_ARN
REGION=$REGION
EOF

echo ""
echo "Deployment complete!"
echo "  State Machine: $STATE_MACHINE_NAME"
echo "  Adam Function: $ADAM_FUNCTION"
echo "  Cole Function: $COLE_FUNCTION"
echo "  Combine Function: $COMBINE_FUNCTION"
