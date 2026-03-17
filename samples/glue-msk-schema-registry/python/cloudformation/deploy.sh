#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR/.."

if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

STACK_NAME="glue-msk-schema-registry"

echo "=== Deploying Glue MSK Schema Registry (CloudFormation) ==="

cd "$SCRIPT_DIR"

# Get two subnets for MSK
SUBNET1=$($AWSCLI ec2 describe-subnets --query "Subnets[0].SubnetId" --output text)
SUBNET2=$($AWSCLI ec2 describe-subnets --query "Subnets[1].SubnetId" --output text)

$AWSCLI cloudformation deploy \
    --template-file template.yml \
    --stack-name "$STACK_NAME" \
    --parameter-overrides "SubnetId1=$SUBNET1" "SubnetId2=$SUBNET2" \
    --no-fail-on-empty-changeset

# Wait for stack
$AWSCLI cloudformation wait stack-create-complete --stack-name "$STACK_NAME" 2>/dev/null || true

# Get outputs
get_output() {
    $AWSCLI cloudformation describe-stacks --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

CLUSTER_NAME=$(get_output ClusterName)
CLUSTER_ARN=$(get_output ClusterArn)
REGISTRY_NAME=$(get_output RegistryName)
REGISTRY_ARN=$(get_output RegistryArn)
SCHEMA_NAME=$(get_output SchemaName)
SCHEMA_ARN=$(get_output SchemaArn)

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
STACK_NAME=$STACK_NAME
EOF

echo "Deployment complete!"
