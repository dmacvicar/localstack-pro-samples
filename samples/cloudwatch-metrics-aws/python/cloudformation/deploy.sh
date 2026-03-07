#!/bin/bash
set -euo pipefail

# CloudWatch Metrics CloudFormation deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="cloudwatch-metrics-aws"

echo "Deploying CloudWatch metrics with CloudFormation..."

cd "$SCRIPT_DIR"

# Deploy stack
awslocal cloudformation deploy \
    --template-file template.yml \
    --stack-name "$STACK_NAME" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

# Wait for stack to complete
echo "Waiting for stack to complete..."
awslocal cloudformation wait stack-create-complete --stack-name "$STACK_NAME" 2>/dev/null || \
awslocal cloudformation wait stack-update-complete --stack-name "$STACK_NAME" 2>/dev/null || true

# Get outputs
get_output() {
    awslocal cloudformation describe-stacks --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

FUNCTION_NAME=$(get_output "FunctionName")
LAMBDA_ARN=$(get_output "LambdaArn")
TOPIC_NAME=$(get_output "TopicName")
TOPIC_ARN=$(get_output "TopicArn")
ALARM_NAME=$(get_output "AlarmName")
TEST_EMAIL=$(get_output "TestEmail")

# Get alarm state
ALARM_STATE=$(awslocal cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --query 'MetricAlarms[0].StateValue' --output text 2>/dev/null || echo "UNKNOWN")

# Check SMTP configuration
SMTP_CONFIGURED="false"
if [ -n "${SMTP_HOST:-}" ]; then
    SMTP_CONFIGURED="true"
fi

echo ""
echo "CloudWatch resources created successfully!"
echo "  Lambda: $FUNCTION_NAME"
echo "  Lambda ARN: $LAMBDA_ARN"
echo "  SNS Topic: $TOPIC_ARN"
echo "  Alarm: $ALARM_NAME"
echo "  Alarm State: $ALARM_STATE"

# Write environment variables
mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" << EOF
FUNCTION_NAME=$FUNCTION_NAME
LAMBDA_ARN=$LAMBDA_ARN
TOPIC_NAME=$TOPIC_NAME
TOPIC_ARN=$TOPIC_ARN
ALARM_NAME=$ALARM_NAME
ALARM_STATE=$ALARM_STATE
TEST_EMAIL=$TEST_EMAIL
SMTP_CONFIGURED=$SMTP_CONFIGURED
EOF

echo ""
echo "Environment written to $ENV_FILE"
