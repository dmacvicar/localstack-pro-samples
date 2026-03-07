#!/bin/bash
set -euo pipefail

# CloudWatch Metrics Terraform deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"

echo "Deploying CloudWatch metrics with Terraform..."

cd "$SCRIPT_DIR"

# Initialize Terraform
tflocal init -input=false

# Apply configuration
tflocal apply -auto-approve -input=false

# Extract outputs
FUNCTION_NAME=$(tflocal output -raw function_name)
LAMBDA_ARN=$(tflocal output -raw lambda_arn)
TOPIC_NAME=$(tflocal output -raw topic_name)
TOPIC_ARN=$(tflocal output -raw topic_arn)
ALARM_NAME=$(tflocal output -raw alarm_name)
TEST_EMAIL=$(tflocal output -raw test_email)

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
