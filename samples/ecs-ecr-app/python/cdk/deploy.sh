#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="EcsEcrAppStack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying ECS ECR Container App via CDK"

cd "$SCRIPT_DIR"

if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

CLUSTER_NAME="ecs-ecr-cdk-cluster"

echo "Step 1: Installing CDK dependencies..."
uv pip install --system -r requirements.txt --quiet 2>/dev/null || true

echo "Step 2: Bootstrapping CDK..."
$CDK bootstrap --quiet 2>/dev/null || true

echo "Step 3: Deploying infrastructure (ECR, VPC, ECS Cluster)..."
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

echo "Step 5: Deploying ECS Service..."
cd "$SCRIPT_DIR"
$CDK deploy --require-approval never --outputs-file cdk-outputs.json \
    --context image_uri="$REPO_URI:latest" 2>&1 | tail -10

echo "Step 6: Waiting for ECS task to start..."
MAX_ATTEMPTS=30
ATTEMPT=1
TASK_ARN=""

while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
    TASK_ARN=$($AWS ecs list-tasks \
        --cluster "$CLUSTER_NAME" \
        --query 'taskArns[0]' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "None")

    if [[ "$TASK_ARN" != "None" ]] && [[ -n "$TASK_ARN" ]]; then
        TASK_STATUS=$($AWS ecs describe-tasks \
            --cluster "$CLUSTER_NAME" \
            --tasks "$TASK_ARN" \
            --query 'tasks[0].lastStatus' \
            --output text \
            --region "$REGION" 2>/dev/null || echo "UNKNOWN")

        if [[ "$TASK_STATUS" == "RUNNING" ]]; then
            echo "  Task is running: $TASK_ARN"
            break
        fi
        echo "  Task status: $TASK_STATUS (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    else
        echo "  Waiting for task to be created (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    fi

    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done

# Get container endpoint
CONTAINER_ENDPOINT=""
if [[ "$TASK_ARN" != "None" ]] && [[ -n "$TASK_ARN" ]]; then
    TASK_DETAILS=$($AWS ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --region "$REGION" 2>/dev/null)

    HOST_PORT=$(echo "$TASK_DETAILS" | jq -r '.tasks[0].containers[0].networkBindings[0].hostPort // empty')
    if [[ -n "$HOST_PORT" ]]; then
        CONTAINER_ENDPOINT="http://localhost.localstack.cloud:$HOST_PORT"
    fi
fi

# Save outputs for tests
cat > "$PROJECT_DIR/scripts/.env" << EOF
REGION=$REGION
REPO_URI=$REPO_URI
REPO_NAME=$REPO_NAME
CLUSTER_NAME=$CLUSTER_NAME
TASK_ARN=$TASK_ARN
CONTAINER_ENDPOINT=$CONTAINER_ENDPOINT
EOF

echo ""
echo "Deployment complete!"
echo "  ECR Repository: $REPO_URI"
echo "  ECS Cluster: $CLUSTER_NAME"
echo "  Task ARN: $TASK_ARN"
if [[ -n "$CONTAINER_ENDPOINT" ]]; then
    echo "  Container Endpoint: $CONTAINER_ENDPOINT"
fi
