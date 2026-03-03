#!/bin/bash
set -euo pipefail

# =============================================================================
# Step Functions Lambda - Test Script (Python)
#
# Tests:
# 1. All Lambda functions exist and are active
# 2. State machine is created with correct definition
# 3. Individual Lambda functions work correctly
# 4. State machine execution completes successfully
# 5. Final output matches expected format
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
    AWS="aws --endpoint-url=http://localhost:4566"
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

echo "Testing Step Functions Lambda Sample"
echo "  State Machine: $STATE_MACHINE_NAME"
echo ""

# =============================================================================
# Test 1: Lambda functions exist and are active
# =============================================================================
echo "Test 1: Lambda functions state"

for func_name in "$ADAM_FUNCTION" "$COLE_FUNCTION" "$COMBINE_FUNCTION"; do
    # Wait for function to be active (up to 30 seconds)
    echo "  Waiting for $func_name to be active..."
    for i in {1..15}; do
        FUNCTION_STATE=$($AWS lambda get-function \
            --function-name "$func_name" \
            --query 'Configuration.State' \
            --output text \
            --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

        if [[ "$FUNCTION_STATE" == "Active" ]]; then
            break
        fi
        sleep 2
    done

    if [[ "$FUNCTION_STATE" == "Active" ]]; then
        pass "$func_name is Active"
    else
        fail "$func_name state is '$FUNCTION_STATE'"
    fi
done

# =============================================================================
# Test 2: State machine exists
# =============================================================================
echo ""
echo "Test 2: State machine exists"

SM_STATUS=$($AWS stepfunctions describe-state-machine \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --query 'status' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

if [[ "$SM_STATUS" == "ACTIVE" ]]; then
    pass "State machine is ACTIVE"
else
    fail "State machine status is '$SM_STATUS'"
fi

# =============================================================================
# Test 3: Individual Lambda invocation - Adam
# =============================================================================
echo ""
echo "Test 3: Direct Lambda invocation - Adam"

ADAM_PAYLOAD='{"input": {"adam": "LocalStack", "cole": "Stack"}}'
echo "$ADAM_PAYLOAD" > /tmp/adam-payload.json

$AWS lambda invoke \
    --function-name "$ADAM_FUNCTION" \
    --payload "file:///tmp/adam-payload.json" \
    --region "$REGION" \
    /tmp/adam-response.json > /dev/null 2>&1

ADAM_RESULT=$(cat /tmp/adam-response.json | tr -d '"')
if [[ "$ADAM_RESULT" == "LocalStack" ]]; then
    pass "Adam Lambda returns 'LocalStack'"
else
    fail "Adam Lambda returned '$ADAM_RESULT' (expected 'LocalStack')"
fi

# =============================================================================
# Test 4: Individual Lambda invocation - Cole
# =============================================================================
echo ""
echo "Test 4: Direct Lambda invocation - Cole"

COLE_PAYLOAD='{"input": {"adam": "LocalStack", "cole": "Stack"}}'
echo "$COLE_PAYLOAD" > /tmp/cole-payload.json

$AWS lambda invoke \
    --function-name "$COLE_FUNCTION" \
    --payload "file:///tmp/cole-payload.json" \
    --region "$REGION" \
    /tmp/cole-response.json > /dev/null 2>&1

COLE_RESULT=$(cat /tmp/cole-response.json | tr -d '"')
if [[ "$COLE_RESULT" == "Stack" ]]; then
    pass "Cole Lambda returns 'Stack'"
else
    fail "Cole Lambda returned '$COLE_RESULT' (expected 'Stack')"
fi

# =============================================================================
# Test 5: Individual Lambda invocation - Combine
# =============================================================================
echo ""
echo "Test 5: Direct Lambda invocation - Combine"

COMBINE_PAYLOAD='{"input": ["LocalStack", "Stack"]}'
echo "$COMBINE_PAYLOAD" > /tmp/combine-payload.json

$AWS lambda invoke \
    --function-name "$COMBINE_FUNCTION" \
    --payload "file:///tmp/combine-payload.json" \
    --region "$REGION" \
    /tmp/combine-response.json > /dev/null 2>&1

COMBINE_RESULT=$(cat /tmp/combine-response.json | tr -d '"')
EXPECTED_COMBINE="Together Adam and Cole say 'LocalStack Stack'!!"
if [[ "$COMBINE_RESULT" == "$EXPECTED_COMBINE" ]]; then
    pass "Combine Lambda returns expected message"
else
    fail "Combine Lambda returned '$COMBINE_RESULT'"
fi

# =============================================================================
# Test 6: State machine execution
# =============================================================================
echo ""
echo "Test 6: State machine execution"

EXECUTION_INPUT='{"adam": "LocalStack", "cole": "Stack"}'
EXECUTION_ARN=$($AWS stepfunctions start-execution \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --input "$EXECUTION_INPUT" \
    --query 'executionArn' \
    --output text \
    --region "$REGION")

if [[ -n "$EXECUTION_ARN" ]]; then
    pass "Execution started: ${EXECUTION_ARN##*:}"
else
    fail "Failed to start execution"
fi

# Wait for execution to complete (with timeout)
echo "  Waiting for execution to complete..."
MAX_ATTEMPTS=30
ATTEMPT=1
EXECUTION_STATUS=""

while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
    EXECUTION_STATUS=$($AWS stepfunctions describe-execution \
        --execution-arn "$EXECUTION_ARN" \
        --query 'status' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "UNKNOWN")

    if [[ "$EXECUTION_STATUS" == "SUCCEEDED" ]] || [[ "$EXECUTION_STATUS" == "FAILED" ]] || [[ "$EXECUTION_STATUS" == "TIMED_OUT" ]]; then
        break
    fi

    sleep 1
    ((ATTEMPT++))
done

if [[ "$EXECUTION_STATUS" == "SUCCEEDED" ]]; then
    pass "Execution completed with SUCCEEDED status"
else
    fail "Execution status is '$EXECUTION_STATUS' (expected 'SUCCEEDED')"
fi

# =============================================================================
# Test 7: Verify execution output
# =============================================================================
echo ""
echo "Test 7: Execution output validation"

if [[ "$EXECUTION_STATUS" == "SUCCEEDED" ]]; then
    EXECUTION_OUTPUT=$($AWS stepfunctions describe-execution \
        --execution-arn "$EXECUTION_ARN" \
        --query 'output' \
        --output text \
        --region "$REGION" | tr -d '"')

    if [[ "$EXECUTION_OUTPUT" == "$EXPECTED_COMBINE" ]]; then
        pass "Execution output matches expected: '$EXECUTION_OUTPUT'"
    else
        fail "Execution output is '$EXECUTION_OUTPUT'"
    fi
else
    fail "Cannot validate output - execution did not succeed"
fi

# =============================================================================
# Cleanup
# =============================================================================
rm -f /tmp/adam-payload.json /tmp/adam-response.json
rm -f /tmp/cole-payload.json /tmp/cole-response.json
rm -f /tmp/combine-payload.json /tmp/combine-response.json

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
