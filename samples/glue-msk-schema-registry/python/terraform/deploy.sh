#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR/.."

if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    TF="terraform"
fi

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

echo "=== Deploying Glue MSK Schema Registry (Terraform) ==="

cd "$SCRIPT_DIR"

$TF init -input=false
$TF apply -auto-approve -input=false

CLUSTER_ARN=$($TF output -raw cluster_arn)
CLUSTER_NAME=$($TF output -raw cluster_name)
REGISTRY_NAME=$($TF output -raw registry_name)
REGISTRY_ARN=$($TF output -raw registry_arn)
SCHEMA_NAME=$($TF output -raw schema_name)
SCHEMA_ARN=$($TF output -raw schema_arn)

# Wait for MSK cluster to become ACTIVE
echo "Waiting for MSK cluster to become ACTIVE..."
for i in {1..60}; do
    STATE=$($AWSCLI kafka describe-cluster \
        --cluster-arn "$CLUSTER_ARN" \
        --query "ClusterInfo.State" --output text 2>/dev/null || echo "CREATING")
    [ "$STATE" = "ACTIVE" ] && break
    echo "State: $STATE, waiting... ($i/60)"
    sleep 5
done

BOOTSTRAP_BROKERS=$($AWSCLI kafka get-bootstrap-brokers \
    --cluster-arn "$CLUSTER_ARN" \
    --query "BootstrapBrokerStringTls || BootstrapBrokerString" --output text)

# Register schema v2 (backward compatible)
echo "Registering schema v2 (backward compatible)..."
SCHEMA_V2=$(cat "$SAMPLE_DIR/schemas/unicorn_ride_request_v2.avsc")
$AWSCLI glue register-schema-version \
    --schema-id "SchemaArn=${SCHEMA_ARN}" \
    --schema-definition "$SCHEMA_V2" > /dev/null 2>&1 || true

# Attempt schema v3 (not backward compatible)
echo "Registering schema v3 (expected to fail compatibility check)..."
SCHEMA_V3=$(cat "$SAMPLE_DIR/schemas/unicorn_ride_request_v3.avsc")
$AWSCLI glue register-schema-version \
    --schema-id "SchemaArn=${SCHEMA_ARN}" \
    --schema-definition "$SCHEMA_V3" > /dev/null 2>&1 || true

cat > "$SCRIPT_DIR/../scripts/.env" << EOF
CLUSTER_NAME=$CLUSTER_NAME
CLUSTER_ARN=$CLUSTER_ARN
BOOTSTRAP_BROKERS=$BOOTSTRAP_BROKERS
REGISTRY_NAME=$REGISTRY_NAME
REGISTRY_ARN=$REGISTRY_ARN
SCHEMA_NAME=$SCHEMA_NAME
SCHEMA_ARN=$SCHEMA_ARN
EOF

echo "Deployment complete!"
