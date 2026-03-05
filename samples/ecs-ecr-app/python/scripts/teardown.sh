#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Tearing down ECS ECR Container App (scripts)"

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

INFRA_STACK="ecs-ecr-sample-infra"
SERVICE_STACK="ecs-ecr-sample-service"
CLUSTER_NAME="ecs-ecr-sample-cluster"
REPO_NAME="ecs-ecr-sample"

# Delete ECS service stack (this stops tasks and removes service)
echo "Deleting service stack..."
$AWS cloudformation delete-stack --stack-name "$SERVICE_STACK" --region "$REGION" 2>/dev/null || true
$AWS cloudformation wait stack-delete-complete --stack-name "$SERVICE_STACK" --region "$REGION" 2>/dev/null || true

# Delete infrastructure stack
echo "Deleting infrastructure stack..."
$AWS cloudformation delete-stack --stack-name "$INFRA_STACK" --region "$REGION" 2>/dev/null || true
$AWS cloudformation wait stack-delete-complete --stack-name "$INFRA_STACK" --region "$REGION" 2>/dev/null || true

# Delete ECR repository (created outside stacks)
echo "Deleting ECR repository..."
$AWS ecr delete-repository --repository-name "$REPO_NAME" --force --region "$REGION" 2>/dev/null || true

# Clean up .env
rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete!"
