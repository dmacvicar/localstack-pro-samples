#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use awslocal if available, otherwise aws with endpoint
if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

STACK_NAME="route53-dns-failover"

echo "=== Deploying Route53 DNS Failover (CloudFormation) ==="

# Deploy the stack
$AWSCLI cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file "$SCRIPT_DIR/template.yml" \
    --no-fail-on-empty-changeset 2>/dev/null || \
$AWSCLI cloudformation create-stack \
    --stack-name "$STACK_NAME" \
    --template-body "file://$SCRIPT_DIR/template.yml"

# Wait for stack to complete
echo "Waiting for stack to complete..."
$AWSCLI cloudformation wait stack-create-complete --stack-name "$STACK_NAME" 2>/dev/null || \
$AWSCLI cloudformation wait stack-update-complete --stack-name "$STACK_NAME" 2>/dev/null || true

# Extract outputs
OUTPUTS=$($AWSCLI cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs')

get_output() {
    echo "$OUTPUTS" | jq -r ".[] | select(.OutputKey==\"$1\") | .OutputValue"
}

HOSTED_ZONE_ID=$(get_output "HostedZoneId")
HOSTED_ZONE_NAME=$(get_output "HostedZoneName")
HEALTH_CHECK_ID=$(get_output "HealthCheckId")
FAILOVER_RECORD=$(get_output "FailoverRecord")
TARGET1_RECORD=$(get_output "Target1Record")
TARGET2_RECORD=$(get_output "Target2Record")

# Save to shared .env
cat > "$SCRIPT_DIR/../scripts/.env" << EOF
HOSTED_ZONE_ID=$HOSTED_ZONE_ID
HOSTED_ZONE_NAME=$HOSTED_ZONE_NAME
HEALTH_CHECK_ID=$HEALTH_CHECK_ID
FAILOVER_RECORD=$FAILOVER_RECORD
TARGET1_RECORD=$TARGET1_RECORD
TARGET2_RECORD=$TARGET2_RECORD
STACK_NAME=$STACK_NAME
EOF

echo ""
echo "Deployment complete!"
echo "Hosted Zone: ${HOSTED_ZONE_NAME}"
echo "Health Check: ${HEALTH_CHECK_ID}"
