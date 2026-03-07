#!/bin/bash
set -euo pipefail

# IAM Policy Enforcement CDK deployment script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SAMPLE_DIR/scripts/.env"
STACK_NAME="IamPolicyEnforcementStack"

echo "Deploying IAM policy enforcement with CDK..."

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

# Install CDK dependencies
pip install -q -r requirements.txt

# Bootstrap CDK (if needed)
cdklocal bootstrap --quiet 2>/dev/null || true

# Deploy
cdklocal deploy "$STACK_NAME" --require-approval never --outputs-file outputs.json

# Extract outputs
USER_NAME=$(jq -r ".[\"$STACK_NAME\"].UserName" outputs.json)
POLICY_NAME=$(jq -r ".[\"$STACK_NAME\"].PolicyName" outputs.json)
POLICY_ARN=$(jq -r ".[\"$STACK_NAME\"].PolicyArn" outputs.json)
ACCESS_KEY_ID=$(jq -r ".[\"$STACK_NAME\"].AccessKeyId" outputs.json)
SECRET_ACCESS_KEY=$(jq -r ".[\"$STACK_NAME\"].SecretAccessKey" outputs.json)

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
