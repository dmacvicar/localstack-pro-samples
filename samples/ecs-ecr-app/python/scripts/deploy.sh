#!/bin/bash
set -euo pipefail

# =============================================================================
# ECS ECR Container App - Deploy Script
#
# Deploys an nginx container to ECS using ECR for image storage and
# CloudFormation for infrastructure provisioning.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying ECS ECR Container App"
echo "  Region: $REGION"
echo ""

# Use aws CLI directly with endpoint-url to avoid awslocal --s3-endpoint-url bug
AWS="aws --endpoint-url=http://localhost:4566"

# =============================================================================
# Step 1: Create ECR Repository
# =============================================================================
echo "Step 1: Creating ECR repository..."

REPO_NAME="ecs-ecr-sample"
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
# Step 2: Build and Push Docker Image
# =============================================================================
echo ""
echo "Step 2: Building and pushing Docker image..."

cd "$PROJECT_DIR"

# Build the image
docker build -t "$REPO_URI:latest" . 2>&1 | tail -5

# Push to ECR (LocalStack doesn't require authentication)
sleep 2  # Brief wait for ECR to be ready
docker push "$REPO_URI:latest" 2>&1 | tail -5

echo "  Image pushed: $REPO_URI:latest"

# =============================================================================
# Step 3: Deploy Infrastructure Stack
# =============================================================================
echo ""
echo "Step 3: Deploying infrastructure stack..."

INFRA_STACK="ecs-ecr-sample-infra"

$AWS cloudformation deploy \
    --stack-name "$INFRA_STACK" \
    --template-file "$PROJECT_DIR/templates/ecs-infra.yml" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --no-fail-on-empty-changeset 2>&1 | grep -v "^$" || true

# Wait for stack to complete
echo "  Waiting for infrastructure stack..."
$AWS cloudformation wait stack-create-complete \
    --stack-name "$INFRA_STACK" \
    --region "$REGION" 2>/dev/null || true

INFRA_STATUS=$($AWS cloudformation describe-stacks \
    --stack-name "$INFRA_STACK" \
    --query 'Stacks[0].StackStatus' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "UNKNOWN")

if [[ "$INFRA_STATUS" != *"COMPLETE"* ]]; then
    echo "  Warning: Infrastructure stack status: $INFRA_STATUS"
fi

echo "  Infrastructure stack deployed"

# =============================================================================
# Step 4: Deploy Service Stack
# =============================================================================
echo ""
echo "Step 4: Deploying service stack..."

SERVICE_STACK="ecs-ecr-sample-service"

$AWS cloudformation deploy \
    --stack-name "$SERVICE_STACK" \
    --template-file "$PROJECT_DIR/templates/ecs-service.yml" \
    --parameter-overrides "ImageUri=$REPO_URI:latest" \
    --region "$REGION" \
    --no-fail-on-empty-changeset 2>&1 | grep -v "^$" || true

# Wait for stack to complete
echo "  Waiting for service stack..."
$AWS cloudformation wait stack-create-complete \
    --stack-name "$SERVICE_STACK" \
    --region "$REGION" 2>/dev/null || true

SERVICE_STATUS=$($AWS cloudformation describe-stacks \
    --stack-name "$SERVICE_STACK" \
    --query 'Stacks[0].StackStatus' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "UNKNOWN")

if [[ "$SERVICE_STATUS" != *"COMPLETE"* ]]; then
    echo "  Warning: Service stack status: $SERVICE_STATUS"
fi

echo "  Service stack deployed"

# =============================================================================
# Step 5: Wait for ECS Task to be Running
# =============================================================================
echo ""
echo "Step 5: Waiting for ECS task to start..."

CLUSTER_NAME="ecs-ecr-sample-cluster"
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

if [[ $ATTEMPT -gt $MAX_ATTEMPTS ]]; then
    echo "  Warning: Task did not reach RUNNING state within timeout"
fi

# =============================================================================
# Step 6: Get Container Endpoint
# =============================================================================
echo ""
echo "Step 6: Getting container endpoint..."

# Get container endpoint from LocalStack ECS task
CONTAINER_ENDPOINT=""
if [[ "$TASK_ARN" != "None" ]] && [[ -n "$TASK_ARN" ]]; then
    TASK_DETAILS=$($AWS ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --region "$REGION" 2>/dev/null)

    # Try networkBindings first (has hostPort)
    HOST_PORT=$(echo "$TASK_DETAILS" | jq -r '.tasks[0].containers[0].networkBindings[0].hostPort // empty')
    if [[ -n "$HOST_PORT" ]]; then
        CONTAINER_ENDPOINT="http://localhost.localstack.cloud:$HOST_PORT"
    fi

    # Fallback: check attachments for ENI details
    if [[ -z "$CONTAINER_ENDPOINT" ]]; then
        PRIVATE_IP=$(echo "$TASK_DETAILS" | jq -r '.tasks[0].attachments[0].details[] | select(.name=="privateIPv4Address") | .value // empty' 2>/dev/null)
        if [[ -n "$PRIVATE_IP" ]]; then
            CONTAINER_ENDPOINT="http://$PRIVATE_IP:80"
        fi
    fi
fi

# Store endpoint for tests
CONTAINER_ENDPOINT="${CONTAINER_ENDPOINT:-}"

# =============================================================================
# Save Configuration
# =============================================================================
cat > "$SCRIPT_DIR/.env" << EOF
REGION=$REGION
REPO_URI=$REPO_URI
CLUSTER_NAME=$CLUSTER_NAME
TASK_ARN=$TASK_ARN
INFRA_STACK=$INFRA_STACK
SERVICE_STACK=$SERVICE_STACK
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
