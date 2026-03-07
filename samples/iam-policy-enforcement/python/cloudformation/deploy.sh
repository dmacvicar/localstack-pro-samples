#!/bin/bash
set -euo pipefail

# IAM Policy Enforcement CloudFormation deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="iam-policy-enforcement"
USER_NAME="${USER_NAME:-iam-test-user}"

echo "Deploying IAM policy enforcement with CloudFormation..."

# Check if IAM enforcement is enabled
echo "Checking if IAM enforcement is enabled..."
if awslocal kinesis create-stream --stream-name iam-check-stream --shard-count 1 2>/dev/null; then
    awslocal kinesis delete-stream --stream-name iam-check-stream 2>/dev/null || true
    echo "WARNING: IAM enforcement does not appear to be enabled."
    IAM_ENFORCED="false"
else
    echo "IAM enforcement is enabled"
    IAM_ENFORCED="true"
fi

cd "$SCRIPT_DIR"

# Deploy stack
awslocal cloudformation deploy \
    --template-file template.yml \
    --stack-name "$STACK_NAME" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

# Wait for stack to complete
echo "Waiting for stack to complete..."
awslocal cloudformation wait stack-create-complete --stack-name "$STACK_NAME" 2>/dev/null || \
awslocal cloudformation wait stack-update-complete --stack-name "$STACK_NAME" 2>/dev/null || true

# Get outputs
get_output() {
    awslocal cloudformation describe-stacks --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

USER_NAME=$(get_output "UserName")
POLICY_NAME=$(get_output "PolicyName")
POLICY_ARN=$(get_output "PolicyArn")

# Create access key (CloudFormation can't output the secret)
echo "Creating access key..."
# Clean up existing keys first
for key_id in $(awslocal iam list-access-keys --user-name "$USER_NAME" 2>/dev/null | jq -r '.AccessKeyMetadata[].AccessKeyId' 2>/dev/null || true); do
    awslocal iam delete-access-key --user-name "$USER_NAME" --access-key-id "$key_id" 2>/dev/null || true
done

KEY_RESPONSE=$(awslocal iam create-access-key --user-name "$USER_NAME" --output json)
ACCESS_KEY_ID=$(echo "$KEY_RESPONSE" | jq -r '.AccessKey.AccessKeyId')
SECRET_ACCESS_KEY=$(echo "$KEY_RESPONSE" | jq -r '.AccessKey.SecretAccessKey')

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
