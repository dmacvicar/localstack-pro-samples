#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Lambda Container Image via Terraform"

cd "$SCRIPT_DIR"

# Use tflocal for LocalStack
if command -v tflocal &> /dev/null; then
    TF="tflocal"
else
    TF="terraform"
fi

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

echo "Step 1: Initializing Terraform..."
$TF init -input=false

echo "Step 2: Creating ECR repository..."
# Apply just the ECR repository first
$TF apply -auto-approve -target=aws_ecr_repository.lambda_repo -input=false

# Get the repository URI
REPO_URI=$($TF output -raw repo_uri)
echo "  Repository URI: $REPO_URI"

echo "Step 3: Building and pushing Docker image..."
cd "$PROJECT_DIR"
docker build -t "$REPO_URI:latest" . 2>&1 | tail -5
sleep 2
docker push "$REPO_URI:latest" 2>&1 | tail -5

echo "Step 4: Deploying Lambda function..."
cd "$SCRIPT_DIR"
$TF apply -auto-approve -input=false

echo "Step 5: Waiting for function to be active..."
FUNCTION_NAME=$($TF output -raw function_name)
MAX_ATTEMPTS=30
ATTEMPT=1

while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
    STATE=$($AWS lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" \
        --query 'Configuration.State' \
        --output text 2>/dev/null || echo "Pending")

    if [[ "$STATE" == "Active" ]]; then
        echo "  Function is active"
        break
    fi
    echo "  State: $STATE (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done

# Save outputs for tests
REPO_NAME=$($TF output -raw repo_name)

cat > "$PROJECT_DIR/scripts/.env" << EOF
FUNCTION_NAME=$FUNCTION_NAME
REPO_NAME=$REPO_NAME
REPO_URI=$REPO_URI
REGION=$REGION
EOF

echo ""
echo "Deployment complete!"
echo "  ECR Repository: $REPO_URI"
echo "  Lambda Function: $FUNCTION_NAME"
