#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use awslocal if available, otherwise aws with endpoint
if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

# Load environment
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

echo "=== Tearing down Route53 DNS Failover ==="

# Delete failover records
if [ -n "${HOSTED_ZONE_ID:-}" ] && [ -n "${HOSTED_ZONE_NAME:-}" ]; then
    echo "Deleting failover routing records..."
    $AWSCLI route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch '{
        "Changes": [
            {
                "Action": "DELETE",
                "ResourceRecordSet": {
                    "Name": "app.'"$HOSTED_ZONE_NAME"'",
                    "Type": "CNAME",
                    "SetIdentifier": "primary",
                    "AliasTarget": {
                        "HostedZoneId": "'"$HOSTED_ZONE_ID"'",
                        "DNSName": "target1.'"$HOSTED_ZONE_NAME"'",
                        "EvaluateTargetHealth": true
                    },
                    "HealthCheckId": "'"${HEALTH_CHECK_ID:-}"'",
                    "Failover": "PRIMARY"
                }
            },
            {
                "Action": "DELETE",
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
        ]}' 2>/dev/null || true

    echo "Deleting target CNAME records..."
    $AWSCLI route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch '{
        "Changes": [
            {
                "Action": "DELETE",
                "ResourceRecordSet": {
                    "Name": "target1.'"$HOSTED_ZONE_NAME"'",
                    "Type": "CNAME",
                    "TTL": 60,
                    "ResourceRecords": [{"Value": "primary.example.com"}]
                }
            },
            {
                "Action": "DELETE",
                "ResourceRecordSet": {
                    "Name": "target2.'"$HOSTED_ZONE_NAME"'",
                    "Type": "CNAME",
                    "TTL": 60,
                    "ResourceRecords": [{"Value": "secondary.example.com"}]
                }
            }
        ]}' 2>/dev/null || true

    echo "Deleting hosted zone..."
    $AWSCLI route53 delete-hosted-zone --id "$HOSTED_ZONE_ID" 2>/dev/null || true
fi

# Delete health check
if [ -n "${HEALTH_CHECK_ID:-}" ]; then
    echo "Deleting health check..."
    $AWSCLI route53 delete-health-check --health-check-id "$HEALTH_CHECK_ID" 2>/dev/null || true
fi

# Clean up env file
rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete!"
