#!/bin/bash
set -euo pipefail

# IAM Policy Enforcement Terraform deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"

echo "Deploying IAM policy enforcement with Terraform..."

# Check if IAM enforcement is enabled
echo "Checking if IAM enforcement is enabled..."
if awslocal kinesis create-stream --stream-name iam-check-stream --shard-count 1 2>/dev/null; then
    awslocal kinesis delete-stream --stream-name iam-check-stream 2>/dev/null || true
    echo "WARNING: IAM enforcement does not appear to be enabled."
    echo "Start LocalStack with ENFORCE_IAM=1 for this sample to work correctly."
    IAM_ENFORCED="false"
else
    echo "IAM enforcement is enabled"
    IAM_ENFORCED="true"
fi

cd "$SCRIPT_DIR"

# Initialize Terraform
tflocal init -input=false

# Apply configuration
tflocal apply -auto-approve -input=false

# Extract outputs
USER_NAME=$(tflocal output -raw user_name)
POLICY_NAME=$(tflocal output -raw policy_name)
POLICY_ARN=$(tflocal output -raw policy_arn)
ACCESS_KEY_ID=$(tflocal output -raw access_key_id)
SECRET_ACCESS_KEY=$(tflocal output -raw secret_access_key)

echo ""
echo "IAM resources created successfully!"
echo "  User: $USER_NAME"
echo "  Policy: $POLICY_NAME"
echo "  Access Key ID: $ACCESS_KEY_ID"

# Write environment variables
mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" << EOF
USER_NAME=$USER_NAME
POLICY_NAME=$POLICY_NAME
POLICY_ARN=$POLICY_ARN
IAM_ACCESS_KEY_ID=$ACCESS_KEY_ID
IAM_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY
IAM_ENFORCED=$IAM_ENFORCED
EOF

echo ""
echo "Environment written to $ENV_FILE"
