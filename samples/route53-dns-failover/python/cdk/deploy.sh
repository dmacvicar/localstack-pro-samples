#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use cdklocal if available, otherwise cdk
if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

echo "=== Deploying Route53 DNS Failover (CDK) ==="

cd "$SCRIPT_DIR"

# Install dependencies
uv pip install --system -r requirements.txt 2>/dev/null || pip install -r requirements.txt

# Bootstrap CDK
$CDK bootstrap 2>/dev/null || true

# Deploy
$CDK deploy --require-approval never --outputs-file cdk-outputs.json

# Extract outputs
STACK_OUTPUT=$(cat cdk-outputs.json | jq -r '.Route53DnsFailoverStack')
HOSTED_ZONE_ID=$(echo "$STACK_OUTPUT" | jq -r '.HostedZoneId')
HOSTED_ZONE_NAME=$(echo "$STACK_OUTPUT" | jq -r '.HostedZoneName')
HEALTH_CHECK_ID=$(echo "$STACK_OUTPUT" | jq -r '.HealthCheckId')
FAILOVER_RECORD=$(echo "$STACK_OUTPUT" | jq -r '.FailoverRecord')
TARGET1_RECORD=$(echo "$STACK_OUTPUT" | jq -r '.Target1Record')
TARGET2_RECORD=$(echo "$STACK_OUTPUT" | jq -r '.Target2Record')

# Save to shared .env
cat > "$SCRIPT_DIR/../scripts/.env" << EOF
HOSTED_ZONE_ID=$HOSTED_ZONE_ID
HOSTED_ZONE_NAME=$HOSTED_ZONE_NAME
HEALTH_CHECK_ID=$HEALTH_CHECK_ID
FAILOVER_RECORD=$FAILOVER_RECORD
TARGET1_RECORD=$TARGET1_RECORD
TARGET2_RECORD=$TARGET2_RECORD
EOF

echo ""
echo "Deployment complete!"
echo "Hosted Zone: ${HOSTED_ZONE_NAME}"
echo "Health Check: ${HEALTH_CHECK_ID}"
