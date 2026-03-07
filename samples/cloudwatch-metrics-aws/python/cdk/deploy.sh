#!/bin/bash
set -euo pipefail

# CloudWatch Metrics CDK deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="CloudWatchMetricsStack"

echo "Deploying CloudWatch metrics with CDK..."

cd "$SCRIPT_DIR"

# Install CDK dependencies
pip install -q -r requirements.txt

# Bootstrap CDK (if needed)
cdklocal bootstrap --quiet 2>/dev/null || true

# Deploy
cdklocal deploy "$STACK_NAME" --require-approval never --outputs-file outputs.json

# Extract outputs
FUNCTION_NAME=$(jq -r ".[\"$STACK_NAME\"].FunctionName" outputs.json)
LAMBDA_ARN=$(jq -r ".[\"$STACK_NAME\"].LambdaArn" outputs.json)
TOPIC_NAME=$(jq -r ".[\"$STACK_NAME\"].TopicName" outputs.json)
TOPIC_ARN=$(jq -r ".[\"$STACK_NAME\"].TopicArn" outputs.json)
ALARM_NAME=$(jq -r ".[\"$STACK_NAME\"].AlarmName" outputs.json)
TEST_EMAIL=$(jq -r ".[\"$STACK_NAME\"].TestEmail" outputs.json)

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
