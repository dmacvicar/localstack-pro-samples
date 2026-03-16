#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use tflocal if available, otherwise terraform
if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    TF="terraform"
fi

echo "=== Deploying Route53 DNS Failover (Terraform) ==="

cd "$SCRIPT_DIR"

$TF init -input=false
$TF apply -auto-approve -input=false

# Extract outputs
HOSTED_ZONE_ID=$($TF output -raw hosted_zone_id)
HOSTED_ZONE_NAME=$($TF output -raw hosted_zone_name)
HEALTH_CHECK_ID=$($TF output -raw health_check_id)
FAILOVER_RECORD=$($TF output -raw failover_record)
TARGET1_RECORD=$($TF output -raw target1_record)
TARGET2_RECORD=$($TF output -raw target2_record)

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
