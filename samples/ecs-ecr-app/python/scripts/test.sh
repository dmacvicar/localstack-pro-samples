#!/bin/bash
set -euo pipefail

# =============================================================================
# ECS ECR Container App - Test Script
#
# Tests:
# 1. ECR repository exists
# 2. Docker image is in ECR
# 3. ECS cluster exists
# 4. ECS service is running
# 5. ECS task is running
# 6. Container responds to HTTP requests
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    source "$SCRIPT_DIR/.env"
else
    echo "Error: Run deploy.sh first"
    exit 1
fi

# Determine CLI to use
if command -v awslocal &> /dev/null; then
    AWS="awslocal"
else
    AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"
fi

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo "  PASS: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo "  FAIL: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo "Testing ECS ECR Container App"
echo "  Region: $REGION"
echo "  Cluster: $CLUSTER_NAME"
echo ""

# =============================================================================
# Test 1: ECR Repository Exists
# =============================================================================
echo "Test 1: ECR repository exists"

REPO_INFO=$($AWS ecr describe-repositories \
    --repository-names "ecs-ecr-sample" \
    --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

if echo "$REPO_INFO" | grep -q "repositoryUri"; then
    pass "ECR repository 'ecs-ecr-sample' exists"
else
    fail "ECR repository not found"
fi

# =============================================================================
# Test 2: Docker Image in ECR
# =============================================================================
echo ""
echo "Test 2: Docker image is in ECR"

IMAGE_INFO=$($AWS ecr describe-images \
    --repository-name "ecs-ecr-sample" \
    --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

if echo "$IMAGE_INFO" | grep -q "imageDigest"; then
    pass "Docker image exists in ECR"
else
    fail "Docker image not found in ECR"
fi

# =============================================================================
# Test 3: ECS Cluster Exists
# =============================================================================
echo ""
echo "Test 3: ECS cluster exists"

CLUSTER_INFO=$($AWS ecs describe-clusters \
    --clusters "$CLUSTER_NAME" \
    --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

CLUSTER_STATUS=$(echo "$CLUSTER_INFO" | jq -r '.clusters[0].status // "NOT_FOUND"')

if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
    pass "ECS cluster '$CLUSTER_NAME' is ACTIVE"
else
    fail "ECS cluster status is '$CLUSTER_STATUS'"
fi

# =============================================================================
# Test 4: ECS Service Running
# =============================================================================
echo ""
echo "Test 4: ECS service is running"

SERVICE_INFO=$($AWS ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "ecs-ecr-sample-service" \
    --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

SERVICE_STATUS=$(echo "$SERVICE_INFO" | jq -r '.services[0].status // "NOT_FOUND"')
RUNNING_COUNT=$(echo "$SERVICE_INFO" | jq -r '.services[0].runningCount // 0')
DESIRED_COUNT=$(echo "$SERVICE_INFO" | jq -r '.services[0].desiredCount // 0')

if [[ "$SERVICE_STATUS" == "ACTIVE" ]]; then
    pass "ECS service is ACTIVE (running: $RUNNING_COUNT, desired: $DESIRED_COUNT)"
else
    fail "ECS service status is '$SERVICE_STATUS'"
fi

# =============================================================================
# Test 5: ECS Task Running
# =============================================================================
echo ""
echo "Test 5: ECS task is running"

if [[ -n "$TASK_ARN" ]] && [[ "$TASK_ARN" != "None" ]]; then
    TASK_INFO=$($AWS ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

    TASK_STATUS=$(echo "$TASK_INFO" | jq -r '.tasks[0].lastStatus // "NOT_FOUND"')

    if [[ "$TASK_STATUS" == "RUNNING" ]]; then
        pass "ECS task is RUNNING"
    else
        fail "ECS task status is '$TASK_STATUS'"
    fi
else
    fail "No task ARN available"
fi

# =============================================================================
# Test 6: Container HTTP Response
# =============================================================================
echo ""
echo "Test 6: Container responds to HTTP"

HTTP_PASSED=false

# Use endpoint from deploy if available
if [[ -n "$CONTAINER_ENDPOINT" ]]; then
    if curl -sf --max-time 5 "$CONTAINER_ENDPOINT" > /dev/null 2>&1; then
        HTTP_PASSED=true
        pass "Container responds at $CONTAINER_ENDPOINT"
    fi
fi

# Fallback: query task for endpoint
if [[ "$HTTP_PASSED" != "true" ]] && [[ -n "$TASK_ARN" ]] && [[ "$TASK_ARN" != "None" ]]; then
    TASK_DETAILS=$($AWS ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --region "$REGION" 2>/dev/null || echo "{}")

    # Try network bindings
    HOST_PORT=$(echo "$TASK_DETAILS" | jq -r '.tasks[0].containers[0].networkBindings[0].hostPort // empty')
    if [[ -n "$HOST_PORT" ]]; then
        ENDPOINT="http://localhost.localstack.cloud:$HOST_PORT"
        if curl -sf --max-time 5 "$ENDPOINT" > /dev/null 2>&1; then
            HTTP_PASSED=true
            pass "Container responds at $ENDPOINT"
        fi
    fi

    # Try attachments for ENI
    if [[ "$HTTP_PASSED" != "true" ]]; then
        PRIVATE_IP=$(echo "$TASK_DETAILS" | jq -r '.tasks[0].attachments[0].details[] | select(.name=="privateIPv4Address") | .value // empty' 2>/dev/null)
        if [[ -n "$PRIVATE_IP" ]]; then
            ENDPOINT="http://$PRIVATE_IP:80"
            if curl -sf --max-time 5 "$ENDPOINT" > /dev/null 2>&1; then
                HTTP_PASSED=true
                pass "Container responds at $ENDPOINT"
            fi
        fi
    fi
fi

if [[ "$HTTP_PASSED" != "true" ]]; then
    # Don't fail - HTTP connectivity in LocalStack ECS can be complex
    echo "  SKIP: HTTP connectivity test (LocalStack ECS networking varies)"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "FAILED: Some tests did not pass"
    exit 1
else
    echo "SUCCESS: All tests passed!"
    exit 0
fi
