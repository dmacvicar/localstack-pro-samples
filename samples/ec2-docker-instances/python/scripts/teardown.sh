#!/bin/bash
set -euo pipefail

# EC2 Docker Instances teardown script
# Cleans up EC2 instances and resources

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment if exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

INSTANCE_ID="${INSTANCE_ID:-}"
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Tearing down EC2 Docker instance resources..."

# Terminate instance if we have an ID
if [ -n "$INSTANCE_ID" ]; then
    echo "Terminating instance: $INSTANCE_ID"
    awslocal ec2 terminate-instances --instance-ids "$INSTANCE_ID" 2>/dev/null || true

    # Wait for termination
    for i in {1..10}; do
        STATE=$(awslocal ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "terminated")

        if [ "$STATE" = "terminated" ]; then
            echo "Instance terminated"
            break
        fi
        sleep 1
    done
fi

# Clean up any test AMIs we created
for ami in $(awslocal ec2 describe-images --owners self 2>/dev/null | jq -r '.Images[] | select(.Name | startswith("localstack-sample-")) | .ImageId' 2>/dev/null || true); do
    echo "Deregistering AMI: $ami"
    awslocal ec2 deregister-image --image-id "$ami" 2>/dev/null || true
done

# Clean up .env file
rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete"
