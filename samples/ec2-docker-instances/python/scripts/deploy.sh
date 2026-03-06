#!/bin/bash
set -euo pipefail

# EC2 Docker Instances deployment script
# Creates a Docker-backed EC2 instance for testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
AMI_ID="${AMI_ID:-ami-00a001}"
INSTANCE_NAME="${INSTANCE_NAME:-ec2-docker-test}"
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Setting up EC2 Docker instance..."

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is required but not installed"
    exit 1
fi

# Check if EC2_VM_MANAGER=docker is likely enabled
# We do this by checking if our AMI registration works
echo "Checking EC2 Docker backend configuration..."

# Pull and tag the Ubuntu image as an AMI
echo "Preparing Docker-backed AMI: $AMI_ID"
if ! docker images | grep -q "ubuntu.*focal"; then
    echo "Pulling ubuntu:focal image..."
    docker pull ubuntu:focal
fi

# Tag for LocalStack EC2 Docker backend
# Format: localstack-ec2/{name}:{ami-id}
docker tag ubuntu:focal "localstack-ec2/ubuntu-focal-docker-ami:$AMI_ID" 2>/dev/null || true

echo "AMI $AMI_ID is ready"

# Try to run an EC2 instance
echo "Starting EC2 instance with Docker backend..."
INSTANCE_RESPONSE=$(awslocal ec2 run-instances \
    --image-id "$AMI_ID" \
    --count 1 \
    --instance-type t2.micro \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --output json 2>&1) || {
    echo ""
    echo "WARNING: Failed to start EC2 instance."
    echo "Make sure LocalStack is started with EC2_VM_MANAGER=docker"
    echo ""
    echo "Error: $INSTANCE_RESPONSE"

    # Check if this is a Docker backend issue
    if echo "$INSTANCE_RESPONSE" | grep -qi "not supported\|docker\|ami"; then
        echo ""
        echo "EC2 Docker backend may not be enabled."
        echo "Start LocalStack with: EC2_VM_MANAGER=docker"
        EC2_DOCKER_ENABLED="false"
    else
        EC2_DOCKER_ENABLED="unknown"
    fi

    cat > "$SCRIPT_DIR/.env" << EOF
AMI_ID=$AMI_ID
INSTANCE_ID=
INSTANCE_NAME=$INSTANCE_NAME
EC2_DOCKER_ENABLED=$EC2_DOCKER_ENABLED
EOF
    echo "Environment written to $SCRIPT_DIR/.env"
    exit 0
}

INSTANCE_ID=$(echo "$INSTANCE_RESPONSE" | jq -r '.Instances[0].InstanceId')
echo "Instance started: $INSTANCE_ID"

# Wait for instance to be running
echo "Waiting for instance to be running..."
for i in {1..30}; do
    STATE=$(awslocal ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "pending")

    if [ "$STATE" = "running" ]; then
        echo "Instance is running"
        break
    fi
    echo "  State: $STATE (attempt $i/30)"
    sleep 2
done

# Get instance details
INSTANCE_INFO=$(awslocal ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --output json)

PRIVATE_IP=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress // empty')
PUBLIC_IP=$(echo "$INSTANCE_INFO" | jq -r '.Reservations[0].Instances[0].PublicIpAddress // empty')

echo ""
echo "EC2 Docker instance created successfully!"
echo "  Instance ID: $INSTANCE_ID"
echo "  AMI ID: $AMI_ID"
echo "  Private IP: $PRIVATE_IP"
echo "  Public IP: $PUBLIC_IP"

# Write environment variables
cat > "$SCRIPT_DIR/.env" << EOF
AMI_ID=$AMI_ID
INSTANCE_ID=$INSTANCE_ID
INSTANCE_NAME=$INSTANCE_NAME
PRIVATE_IP=$PRIVATE_IP
PUBLIC_IP=$PUBLIC_IP
EC2_DOCKER_ENABLED=true
EOF

echo ""
echo "Environment written to $SCRIPT_DIR/.env"
