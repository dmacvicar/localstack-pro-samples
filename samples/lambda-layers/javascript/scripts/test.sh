#!/bin/bash
set -euo pipefail

# =============================================================================
# Lambda Layers - Test Script (JavaScript/Serverless)
#
# Tests:
# 1. Lambda function exists and is active
# 2. Layer is attached to function
# 3. Function can invoke and use layer code
# 4. Response contains expected output
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

echo "Testing Lambda Layers Sample"
echo "  Function: $FUNCTION_NAME"
echo ""

# =============================================================================
# Test 1: Lambda function exists and is active
# =============================================================================
echo "Test 1: Lambda function exists and is active"

FUNCTION_STATE=$($AWS lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --query 'Configuration.State' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

if [[ "$FUNCTION_STATE" == "Active" ]]; then
    pass "Function '$FUNCTION_NAME' is Active"
else
    fail "Function state is '$FUNCTION_STATE'"
fi

# =============================================================================
# Test 2: Layer is attached to function
# =============================================================================
echo ""
echo "Test 2: Layer is attached to function"

ATTACHED_LAYERS=$($AWS lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --query 'Configuration.Layers[].Arn' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$ATTACHED_LAYERS" ]]; then
    pass "Layer is attached: $ATTACHED_LAYERS"
else
    fail "No layers attached to function"
fi

# =============================================================================
# Test 3: Function invocation succeeds
# =============================================================================
echo ""
echo "Test 3: Function invocation succeeds"

INVOKE_RESULT=$($AWS lambda invoke \
    --function-name "$FUNCTION_NAME" \
    --payload '{}' \
    --region "$REGION" \
    /tmp/lambda-layers-response.json 2>&1)

if [[ -f /tmp/lambda-layers-response.json ]]; then
    RESPONSE=$(cat /tmp/lambda-layers-response.json)
    STATUS_CODE=$(echo "$RESPONSE" | jq -r '.statusCode' 2>/dev/null || echo "")

    if [[ "$STATUS_CODE" == "200" ]]; then
        pass "Function returned status code 200"
    else
        fail "Function returned status code '$STATUS_CODE'"
    fi
else
    fail "No response file created"
fi

# =============================================================================
# Test 4: Response body contains expected message
# =============================================================================
echo ""
echo "Test 4: Response body validation"

if [[ -f /tmp/lambda-layers-response.json ]]; then
    BODY=$(echo "$RESPONSE" | jq -r '.body' 2>/dev/null || echo "{}")
    MESSAGE=$(echo "$BODY" | jq -r '.message' 2>/dev/null || echo "")
    LAYER_WORKING=$(echo "$BODY" | jq -r '.layerWorking' 2>/dev/null || echo "")

    if [[ "$MESSAGE" == "Hello from Lambda Layer!" ]]; then
        pass "Message is correct: '$MESSAGE'"
    else
        fail "Message is '$MESSAGE' (expected 'Hello from Lambda Layer!')"
    fi

    if [[ "$LAYER_WORKING" == "true" ]]; then
        pass "Layer working flag is true"
    else
        fail "Layer working flag is '$LAYER_WORKING'"
    fi
else
    fail "Cannot validate response - no response file"
    fail "Cannot validate layer flag - no response file"
fi

# =============================================================================
# Test 5: Function does not have import errors
# =============================================================================
echo ""
echo "Test 5: No import/module errors"

if [[ -f /tmp/lambda-layers-response.json ]]; then
    ERROR_TYPE=$(echo "$RESPONSE" | jq -r '.errorType' 2>/dev/null || echo "null")
    ERROR_MSG=$(echo "$RESPONSE" | jq -r '.errorMessage' 2>/dev/null || echo "null")

    if [[ "$ERROR_TYPE" == "null" ]] && [[ "$ERROR_MSG" == "null" ]]; then
        pass "No errors in response"
    else
        fail "Error detected: $ERROR_TYPE - $ERROR_MSG"
    fi
fi

# =============================================================================
# Cleanup
# =============================================================================
rm -f /tmp/lambda-layers-response.json

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
