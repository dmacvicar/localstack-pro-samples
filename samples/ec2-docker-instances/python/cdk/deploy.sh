#!/bin/bash
set -euo pipefail

# EC2 Docker Instances CDK deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="Ec2DockerInstancesStack"

# Configuration
AMI_ID="${AMI_ID:-ami-00a001}"
export AMI_ID

echo "Deploying EC2 Docker instances with CDK..."

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is required but not installed"
    exit 1
fi

# Prepare Docker-backed AMI
echo "Preparing Docker-backed AMI: $AMI_ID"
if ! docker images | grep -q "ubuntu.*focal"; then
    echo "Pulling ubuntu:focal image..."
    docker pull ubuntu:focal
fi
docker tag ubuntu:focal "localstack-ec2/ubuntu-focal-docker-ami:$AMI_ID" 2>/dev/null || true

cd "$SCRIPT_DIR"

# Install CDK dependencies
pip install -q -r requirements.txt

# Bootstrap CDK (if needed)
cdklocal bootstrap --quiet 2>/dev/null || true

# Deploy
if ! cdklocal deploy "$STACK_NAME" --require-approval never --outputs-file outputs.json 2>&1; then
    echo ""
    echo "WARNING: Failed to create EC2 instance."
    echo "Make sure LocalStack is started with EC2_VM_MANAGER=docker"

    mkdir -p "$(dirname "$ENV_FILE")"
    cat > "$ENV_FILE" << EOF
AMI_ID=$AMI_ID
INSTANCE_ID=
INSTANCE_NAME=ec2-docker-test
EC2_DOCKER_ENABLED=false
EOF
    exit 1
fi

# Extract outputs
AMI_ID=$(jq -r ".[\"$STACK_NAME\"].AmiId" outputs.json)
INSTANCE_ID=$(jq -r ".[\"$STACK_NAME\"].InstanceId" outputs.json)
INSTANCE_NAME=$(jq -r ".[\"$STACK_NAME\"].InstanceName" outputs.json)
PRIVATE_IP=$(jq -r ".[\"$STACK_NAME\"].PrivateIp // empty" outputs.json)
PUBLIC_IP=$(jq -r ".[\"$STACK_NAME\"].PublicIp // empty" outputs.json)

echo ""
echo "EC2 Docker instance created successfully!"
echo "  Instance ID: $INSTANCE_ID"
echo "  AMI ID: $AMI_ID"
echo "  Private IP: $PRIVATE_IP"
echo "  Public IP: $PUBLIC_IP"

# Write environment variables
mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" << EOF
AMI_ID=$AMI_ID
INSTANCE_ID=$INSTANCE_ID
INSTANCE_NAME=$INSTANCE_NAME
PRIVATE_IP=$PRIVATE_IP
PUBLIC_IP=$PUBLIC_IP
EC2_DOCKER_ENABLED=true
EOF

echo ""
echo "Environment written to $ENV_FILE"
