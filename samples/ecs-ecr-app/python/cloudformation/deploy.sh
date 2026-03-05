#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="ecs-ecr-cfn-stack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying ECS ECR Container App via CloudFormation"

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

REPO_NAME="ecs-ecr-cfn"
CLUSTER_NAME="ecs-ecr-cfn-cluster"

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
    --parameter-overrides "ImageUri=$REPO_URI:latest" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --no-fail-on-empty-changeset 2>&1 | grep -v "^$" || true

# Wait for stack to complete
echo "  Waiting for stack..."
$AWS cloudformation wait stack-create-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION" 2>/dev/null || true

echo "Step 4: Waiting for ECS task to start..."
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
STACK_NAME=$STACK_NAME
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
