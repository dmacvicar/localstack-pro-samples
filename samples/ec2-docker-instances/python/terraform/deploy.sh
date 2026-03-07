#!/bin/bash
set -euo pipefail

# EC2 Docker Instances Terraform deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"

# Configuration
AMI_ID="${AMI_ID:-ami-00a001}"

echo "Deploying EC2 Docker instances with Terraform..."

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

# Initialize Terraform
tflocal init -input=false

# Apply configuration
if ! tflocal apply -auto-approve -input=false 2>&1; then
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
AMI_ID=$(tflocal output -raw ami_id)
INSTANCE_ID=$(tflocal output -raw instance_id)
INSTANCE_NAME=$(tflocal output -raw instance_name)
PRIVATE_IP=$(tflocal output -raw private_ip 2>/dev/null || echo "")
PUBLIC_IP=$(tflocal output -raw public_ip 2>/dev/null || echo "")

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
