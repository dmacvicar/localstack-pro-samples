#!/bin/bash
set -euo pipefail

# =============================================================================
# Lambda Container Image - Deploy Script
#
# Deploys a Lambda function from a container image stored in ECR.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Lambda Container Image Sample"
echo "  Region: $REGION"
echo ""

# Use aws CLI directly with endpoint-url to avoid awslocal bugs
AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

# =============================================================================
# Step 1: Create ECR Repository
# =============================================================================
echo "Step 1: Creating ECR repository..."

REPO_NAME="lambda-container-sample"
REPO_URI=$($AWS ecr create-repository \
    --repository-name "$REPO_NAME" \
    --region "$REGION" \
    --query 'repository.repositoryUri' \
    --output text 2>/dev/null || \
    $AWS ecr describe-repositories \
        --repository-names "$REPO_NAME" \
        --region "$REGION" \
        --query 'repositories[0].repositoryUri' \
        --output text)

echo "  Repository URI: $REPO_URI"

# =============================================================================
# Step 2: Build Docker Image
# =============================================================================
echo ""
echo "Step 2: Building Docker image..."

cd "$PROJECT_DIR"
docker build -t "$REPO_URI:latest" . 2>&1 | tail -5

echo "  Image built: $REPO_URI:latest"

# =============================================================================
# Step 3: Push to ECR
# =============================================================================
echo ""
echo "Step 3: Pushing image to ECR..."

# LocalStack ECR doesn't require authentication
sleep 2  # Brief wait for ECR to be ready
docker push "$REPO_URI:latest" 2>&1 | tail -5

echo "  Image pushed successfully"

# =============================================================================
# Step 4: Create Lambda Function
# =============================================================================
echo ""
echo "Step 4: Creating Lambda function from container image..."

FUNCTION_NAME="lambda-container-sample"

# Delete existing function if it exists
$AWS lambda delete-function \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" 2>/dev/null || true

# Create function from container image
$AWS lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --package-type Image \
    --code "ImageUri=$REPO_URI:latest" \
    --role "arn:aws:iam::000000000000:role/lambda-role" \
    --timeout 30 \
    --memory-size 256 \
    --region "$REGION" > /dev/null

echo "  Function created: $FUNCTION_NAME"

# =============================================================================
# Step 5: Wait for Function to be Active
# =============================================================================
echo ""
echo "Step 5: Waiting for function to be active..."

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

if [[ $ATTEMPT -gt $MAX_ATTEMPTS ]]; then
    echo "  Warning: Function did not become active within timeout"
fi

# =============================================================================
# Save Configuration
# =============================================================================
cat > "$SCRIPT_DIR/.env" << EOF
FUNCTION_NAME=$FUNCTION_NAME
REPO_NAME=$REPO_NAME
REPO_URI=$REPO_URI
REGION=$REGION
EOF

echo ""
echo "Deployment complete!"
echo "  ECR Repository: $REPO_URI"
echo "  Lambda Function: $FUNCTION_NAME"
