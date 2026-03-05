#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="lambda-container-image-stack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Lambda Container Image via CloudFormation"

# Use aws CLI directly to avoid awslocal bugs
AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

cd "$SCRIPT_DIR"

REPO_NAME="lambda-container-cfn"
FUNCTION_NAME="lambda-container-cfn"

echo "Step 1: Creating ECR repository..."
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

echo "Step 2: Building and pushing Docker image..."
cd "$PROJECT_DIR"
docker build -t "$REPO_URI:latest" . 2>&1 | tail -5
sleep 2
docker push "$REPO_URI:latest" 2>&1 | tail -5

echo "Step 3: Deploying CloudFormation stack..."
cd "$SCRIPT_DIR"
$AWS cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file template.yml \
    --parameter-overrides \
        "FunctionName=$FUNCTION_NAME" \
        "RepoName=$REPO_NAME" \
        "ImageUri=$REPO_URI:latest" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --no-fail-on-empty-changeset

echo "Step 4: Waiting for function to be active..."
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
