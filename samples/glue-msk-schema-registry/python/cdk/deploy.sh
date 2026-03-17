#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR/.."

if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

echo "=== Deploying Glue MSK Schema Registry (CDK) ==="

cd "$SCRIPT_DIR"

uv pip install --system -r requirements.txt 2>/dev/null || pip install -r requirements.txt

# Get two subnets for MSK
SUBNET1=$($AWSCLI ec2 describe-subnets --query "Subnets[0].SubnetId" --output text)
SUBNET2=$($AWSCLI ec2 describe-subnets --query "Subnets[1].SubnetId" --output text)

$CDK bootstrap 2>/dev/null || true
$CDK deploy --require-approval never --outputs-file cdk-outputs.json \
    --parameters "SubnetId1=$SUBNET1" --parameters "SubnetId2=$SUBNET2"

STACK_OUTPUT=$(cat cdk-outputs.json | jq -r '.GlueMskSchemaRegistryStack')

CLUSTER_NAME=$(echo "$STACK_OUTPUT" | jq -r '.ClusterName')
CLUSTER_ARN=$(echo "$STACK_OUTPUT" | jq -r '.ClusterArn')
REGISTRY_NAME=$(echo "$STACK_OUTPUT" | jq -r '.RegistryName')
REGISTRY_ARN=$(echo "$STACK_OUTPUT" | jq -r '.RegistryArn')
SCHEMA_NAME=$(echo "$STACK_OUTPUT" | jq -r '.SchemaName')
SCHEMA_ARN=$(echo "$STACK_OUTPUT" | jq -r '.SchemaArn')

# Wait for MSK cluster
echo "Waiting for MSK cluster to become ACTIVE..."
for i in {1..60}; do
    STATE=$($AWSCLI kafka describe-cluster \
        --cluster-arn "$CLUSTER_ARN" \
        --query "ClusterInfo.State" --output text 2>/dev/null || echo "CREATING")
    [ "$STATE" = "ACTIVE" ] && break
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
