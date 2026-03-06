#!/bin/bash
set -euo pipefail

# IAM Policy Enforcement deployment script
# Creates IAM user with policy for testing IAM enforcement

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
USER_NAME="${USER_NAME:-iam-test-user}"
POLICY_NAME="${POLICY_NAME:-iam-test-policy}"
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Setting up IAM policy enforcement test resources..."

# Check if ENFORCE_IAM is likely enabled by testing a denied action
# We try to create a stream with default credentials - if IAM is enforced, this should fail
echo "Checking if IAM enforcement is enabled..."
if awslocal kinesis create-stream --stream-name iam-check-stream --shard-count 1 2>/dev/null; then
    # Stream created successfully - IAM not enforced, clean up
    awslocal kinesis delete-stream --stream-name iam-check-stream 2>/dev/null || true
    echo ""
    echo "WARNING: IAM enforcement does not appear to be enabled."
    echo "Start LocalStack with ENFORCE_IAM=1 for this sample to work correctly."
    echo ""
    IAM_ENFORCED="false"
else
    echo "IAM enforcement is enabled (default credentials denied)"
    IAM_ENFORCED="true"
fi

# Clean up any existing resources
awslocal iam detach-user-policy --user-name "$USER_NAME" --policy-arn "arn:aws:iam::000000000000:policy/$POLICY_NAME" 2>/dev/null || true
awslocal iam delete-policy --policy-arn "arn:aws:iam::000000000000:policy/$POLICY_NAME" 2>/dev/null || true

# Delete existing access keys for user
for key_id in $(awslocal iam list-access-keys --user-name "$USER_NAME" 2>/dev/null | jq -r '.AccessKeyMetadata[].AccessKeyId' 2>/dev/null || true); do
    awslocal iam delete-access-key --user-name "$USER_NAME" --access-key-id "$key_id" 2>/dev/null || true
done
awslocal iam delete-user --user-name "$USER_NAME" 2>/dev/null || true

# Create IAM policy that allows Kinesis and S3 access
echo "Creating IAM policy: $POLICY_NAME"
POLICY_DOC='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowKinesisAndS3",
            "Effect": "Allow",
            "Action": [
                "kinesis:*",
                "s3:*"
            ],
            "Resource": "*"
        }
    ]
}'

POLICY_RESPONSE=$(awslocal iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "$POLICY_DOC" \
    --output json)

POLICY_ARN=$(echo "$POLICY_RESPONSE" | jq -r '.Policy.Arn')
echo "Created policy: $POLICY_ARN"

# Create IAM user
echo "Creating IAM user: $USER_NAME"
awslocal iam create-user --user-name "$USER_NAME" >/dev/null

# Attach policy to user
echo "Attaching policy to user..."
awslocal iam attach-user-policy \
    --user-name "$USER_NAME" \
    --policy-arn "$POLICY_ARN"

# Create access key for user
echo "Creating access key..."
KEY_RESPONSE=$(awslocal iam create-access-key --user-name "$USER_NAME" --output json)

ACCESS_KEY_ID=$(echo "$KEY_RESPONSE" | jq -r '.AccessKey.AccessKeyId')
SECRET_ACCESS_KEY=$(echo "$KEY_RESPONSE" | jq -r '.AccessKey.SecretAccessKey')

echo ""
echo "IAM resources created successfully!"
echo "  User: $USER_NAME"
echo "  Policy: $POLICY_NAME"
echo "  Access Key ID: $ACCESS_KEY_ID"

# Write environment variables
cat > "$SCRIPT_DIR/.env" << EOF
USER_NAME=$USER_NAME
POLICY_NAME=$POLICY_NAME
POLICY_ARN=$POLICY_ARN
IAM_ACCESS_KEY_ID=$ACCESS_KEY_ID
IAM_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY
IAM_ENFORCED=$IAM_ENFORCED
EOF

echo ""
echo "Environment written to $SCRIPT_DIR/.env"
