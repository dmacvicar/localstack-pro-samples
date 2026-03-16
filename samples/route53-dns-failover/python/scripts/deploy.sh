#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use awslocal if available, otherwise aws with endpoint
if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

SUFFIX="${SUFFIX:-$(date +%s)}"
HOSTED_ZONE_NAME="failover-${SUFFIX}.example.com"

echo "=== Route53 DNS Failover Sample ==="

# Step 1: Create hosted zone
echo "Creating hosted zone: ${HOSTED_ZONE_NAME}..."
HOSTED_ZONE_RESPONSE=$($AWSCLI route53 create-hosted-zone \
    --name "$HOSTED_ZONE_NAME" \
    --caller-reference "failover-${SUFFIX}")
HOSTED_ZONE_ID=$(echo "$HOSTED_ZONE_RESPONSE" | jq -r '.HostedZone.Id' | sed 's|/hostedzone/||')
echo "Hosted Zone ID: ${HOSTED_ZONE_ID}"

# Step 2: Create a health check
echo "Creating health check..."
HEALTH_CHECK_RESPONSE=$($AWSCLI route53 create-health-check \
    --caller-reference "hc-${SUFFIX}" \
    --health-check-config '{
        "FullyQualifiedDomainName": "localhost.localstack.cloud",
        "Port": 4566,
        "ResourcePath": "/_localstack/health",
        "Type": "HTTP",
        "RequestInterval": 10
    }')
HEALTH_CHECK_ID=$(echo "$HEALTH_CHECK_RESPONSE" | jq -r '.HealthCheck.Id')
echo "Health Check ID: ${HEALTH_CHECK_ID}"

# Step 3: Create target CNAME records
echo "Creating target CNAME records..."
$AWSCLI route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch '{
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "target1.'"$HOSTED_ZONE_NAME"'",
                "Type": "CNAME",
                "TTL": 60,
                "ResourceRecords": [{"Value": "primary.example.com"}]
            }
        },
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "target2.'"$HOSTED_ZONE_NAME"'",
                "Type": "CNAME",
                "TTL": 60,
                "ResourceRecords": [{"Value": "secondary.example.com"}]
            }
        }
    ]}'

# Step 4: Create failover routing records
echo "Creating failover routing records..."
$AWSCLI route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch '{
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "app.'"$HOSTED_ZONE_NAME"'",
                "Type": "CNAME",
                "SetIdentifier": "primary",
                "AliasTarget": {
                    "HostedZoneId": "'"$HOSTED_ZONE_ID"'",
                    "DNSName": "target1.'"$HOSTED_ZONE_NAME"'",
                    "EvaluateTargetHealth": true
                },
                "HealthCheckId": "'"$HEALTH_CHECK_ID"'",
                "Failover": "PRIMARY"
            }
        },
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "app.'"$HOSTED_ZONE_NAME"'",
                "Type": "CNAME",
                "SetIdentifier": "secondary",
                "AliasTarget": {
                    "HostedZoneId": "'"$HOSTED_ZONE_ID"'",
                    "DNSName": "target2.'"$HOSTED_ZONE_NAME"'",
                    "EvaluateTargetHealth": true
                },
                "Failover": "SECONDARY"
            }
        }
    ]}'

# Save configuration
cat > "$SCRIPT_DIR/.env" << EOF
HOSTED_ZONE_ID=$HOSTED_ZONE_ID
HOSTED_ZONE_NAME=$HOSTED_ZONE_NAME
HEALTH_CHECK_ID=$HEALTH_CHECK_ID
FAILOVER_RECORD=app.${HOSTED_ZONE_NAME}
TARGET1_RECORD=target1.${HOSTED_ZONE_NAME}
TARGET2_RECORD=target2.${HOSTED_ZONE_NAME}
EOF

echo ""
echo "Deployment complete!"
echo "Hosted Zone: ${HOSTED_ZONE_NAME}"
echo "Health Check: ${HEALTH_CHECK_ID}"
echo "Failover Record: app.${HOSTED_ZONE_NAME}"
