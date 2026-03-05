#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="LambdaContainerImageStack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying Lambda Container Image via CDK"

cd "$SCRIPT_DIR"

if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

AWS="aws --endpoint-url=http://localhost:4566"

echo "Step 1: Installing CDK dependencies..."
uv pip install --system -r requirements.txt --quiet 2>/dev/null || true

echo "Step 2: Bootstrapping CDK..."
$CDK bootstrap --quiet 2>/dev/null || true

echo "Step 3: Deploying ECR repository..."
$CDK deploy --require-approval never --outputs-file cdk-outputs.json 2>&1 | tail -10

# Get the repository URI
REPO_URI=$(jq -r ".$STACK_NAME.RepoUri" cdk-outputs.json)
REPO_NAME=$(jq -r ".$STACK_NAME.RepoName" cdk-outputs.json)
echo "  Repository URI: $REPO_URI"

echo "Step 4: Building and pushing Docker image..."
cd "$PROJECT_DIR"
docker build -t "$REPO_URI:latest" . 2>&1 | tail -5
sleep 2
docker push "$REPO_URI:latest" 2>&1 | tail -5

echo "Step 5: Deploying Lambda function..."
cd "$SCRIPT_DIR"
$CDK deploy --require-approval never --outputs-file cdk-outputs.json \
    --context image_uri="$REPO_URI:latest" 2>&1 | tail -10

echo "Step 6: Waiting for function to be active..."
FUNCTION_NAME=$(jq -r ".$STACK_NAME.FunctionName" cdk-outputs.json)
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
