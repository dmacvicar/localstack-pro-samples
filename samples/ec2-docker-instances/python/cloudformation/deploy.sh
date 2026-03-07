#!/bin/bash
set -euo pipefail

# EC2 Docker Instances CloudFormation deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="ec2-docker-instances"

# Configuration
AMI_ID="${AMI_ID:-ami-00a001}"

echo "Deploying EC2 Docker instances with CloudFormation..."

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

# Deploy stack
if ! awslocal cloudformation deploy \
    --template-file template.yml \
    --stack-name "$STACK_NAME" \
    --parameter-overrides AmiId="$AMI_ID" \
    --no-fail-on-empty-changeset 2>&1; then

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

# Wait for stack to complete
echo "Waiting for stack to complete..."
awslocal cloudformation wait stack-create-complete --stack-name "$STACK_NAME" 2>/dev/null || \
awslocal cloudformation wait stack-update-complete --stack-name "$STACK_NAME" 2>/dev/null || true

# Get outputs
get_output() {
    awslocal cloudformation describe-stacks --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

AMI_ID=$(get_output "AmiId")
INSTANCE_ID=$(get_output "InstanceId")
INSTANCE_NAME=$(get_output "InstanceName")
PRIVATE_IP=$(get_output "PrivateIp")
PUBLIC_IP=$(get_output "PublicIp")

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
