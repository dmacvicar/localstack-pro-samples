#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$SCRIPT_DIR/.."

# Use awslocal if available, otherwise aws with endpoint
if command -v awslocal &> /dev/null; then
    AWSCLI="awslocal"
else
    AWSCLI="aws --endpoint-url=${LOCALSTACK_ENDPOINT:-http://localhost.localstack.cloud:4566}"
fi

SUFFIX="${SUFFIX:-$(date +%s)}"
CLUSTER_NAME="msk-cluster-${SUFFIX}"
REGISTRY_NAME="registry-${SUFFIX}"
SCHEMA_NAME="schema-${SUFFIX}"

echo "=== Glue MSK Schema Registry Sample ==="

# Get two subnets for MSK (requires 2 or 3)
SUBNETS=$($AWSCLI ec2 describe-subnets --query "Subnets[0:2].SubnetId" --output json)

# Step 1: Create MSK cluster
echo "Creating MSK cluster: ${CLUSTER_NAME}..."
CLUSTER_ARN=$($AWSCLI kafka create-cluster \
    --cluster-name "$CLUSTER_NAME" \
    --kafka-version "3.5.1" \
    --number-of-broker-nodes 2 \
    --broker-node-group-info "{\"ClientSubnets\": $SUBNETS, \"InstanceType\":\"kafka.m5.xlarge\"}" \
    --query "ClusterArn" --output text)

echo "Waiting for MSK cluster to become ACTIVE..."
for i in {1..60}; do
    STATE=$($AWSCLI kafka describe-cluster \
        --cluster-arn "$CLUSTER_ARN" \
        --query "ClusterInfo.State" --output text 2>/dev/null || echo "CREATING")
    if [ "$STATE" = "ACTIVE" ]; then
        echo "MSK cluster is ACTIVE"
        break
    fi
    if [ "$STATE" = "FAILED" ]; then
        echo "MSK cluster creation FAILED"
        exit 1
    fi
    echo "State: $STATE, waiting... ($i/60)"
    sleep 5
done

# Get bootstrap brokers
BOOTSTRAP_BROKERS=$($AWSCLI kafka get-bootstrap-brokers \
    --cluster-arn "$CLUSTER_ARN" \
    --query "BootstrapBrokerStringTls || BootstrapBrokerString" --output text)

echo "Bootstrap brokers: ${BOOTSTRAP_BROKERS}"

# Step 2: Create Glue Schema Registry
echo "Creating Glue Schema Registry: ${REGISTRY_NAME}..."
REGISTRY_ARN=$($AWSCLI glue create-registry \
    --registry-name "$REGISTRY_NAME" \
    --query "RegistryArn" --output text)

# Step 3: Create schema v1 with BACKWARD compatibility
echo "Creating AVRO schema v1 with BACKWARD compatibility..."
SCHEMA_V1=$(cat "$SAMPLE_DIR/schemas/unicorn_ride_request_v1.avsc")
SCHEMA_ARN=$($AWSCLI glue create-schema \
    --registry-id "RegistryName=${REGISTRY_NAME}" \
    --schema-name "$SCHEMA_NAME" \
    --compatibility BACKWARD \
    --data-format AVRO \
    --schema-definition "$SCHEMA_V1" \
    --query "SchemaArn" --output text)

# Step 4: Register schema v2 (backward compatible - removes customer field)
echo "Registering schema v2 (backward compatible)..."
SCHEMA_V2=$(cat "$SAMPLE_DIR/schemas/unicorn_ride_request_v2.avsc")
V2_RESULT=$($AWSCLI glue register-schema-version \
    --schema-id "SchemaArn=${SCHEMA_ARN}" \
    --schema-definition "$SCHEMA_V2" 2>&1)
V2_VERSION_NUMBER=$(echo "$V2_RESULT" | jq -r '.VersionNumber // empty' 2>/dev/null || echo "")
V2_STATUS=$(echo "$V2_RESULT" | jq -r '.Status // empty' 2>/dev/null || echo "")
echo "Schema v2: version=${V2_VERSION_NUMBER}, status=${V2_STATUS}"

# Step 5: Attempt schema v3 (NOT backward compatible - adds required field)
echo "Registering schema v3 (expected to fail compatibility check)..."
SCHEMA_V3=$(cat "$SAMPLE_DIR/schemas/unicorn_ride_request_v3.avsc")
V3_RESULT=$($AWSCLI glue register-schema-version \
    --schema-id "SchemaArn=${SCHEMA_ARN}" \
    --schema-definition "$SCHEMA_V3" 2>&1 || true)
V3_VERSION_NUMBER=$(echo "$V3_RESULT" | jq -r '.VersionNumber // empty' 2>/dev/null || echo "")
V3_STATUS=$(echo "$V3_RESULT" | jq -r '.Status // empty' 2>/dev/null || echo "")
echo "Schema v3: version=${V3_VERSION_NUMBER}, status=${V3_STATUS}"

# Save configuration
cat > "$SCRIPT_DIR/.env" << EOF
CLUSTER_NAME=$CLUSTER_NAME
CLUSTER_ARN=$CLUSTER_ARN
BOOTSTRAP_BROKERS=$BOOTSTRAP_BROKERS
REGISTRY_NAME=$REGISTRY_NAME
REGISTRY_ARN=$REGISTRY_ARN
SCHEMA_NAME=$SCHEMA_NAME
SCHEMA_ARN=$SCHEMA_ARN
EOF

echo ""
echo "Deployment complete!"
echo "MSK Cluster: ${CLUSTER_NAME}"
echo "Registry: ${REGISTRY_NAME}"
echo "Schema: ${SCHEMA_NAME}"
