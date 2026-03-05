#!/bin/bash
set -euo pipefail

# =============================================================================
# Lambda Function URLs - Test Script (Python)
#
# Tests:
# 1. Lambda function exists and is active
# 2. Function URL is configured correctly
# 3. Direct Lambda invocation works
# 4. HTTP invocation via Function URL works
# 5. Request payload is processed correctly
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

echo "Testing Lambda Function URL Sample (Python)"
echo "  Function: $FUNCTION_NAME"
echo ""

# =============================================================================
# Test 1: Lambda function exists and is active
# =============================================================================
echo "Test 1: Lambda function state"

FUNCTION_STATE=$($AWS lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --query 'Configuration.State' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

if [[ "$FUNCTION_STATE" == "Active" ]]; then
    pass "Function is Active"
else
    fail "Function state is '$FUNCTION_STATE' (expected 'Active')"
fi

# =============================================================================
# Test 2: Function URL is configured
# =============================================================================
echo ""
echo "Test 2: Function URL configuration"

URL_CONFIG=$($AWS lambda get-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$URL_CONFIG" ]]; then
    AUTH_TYPE=$(echo "$URL_CONFIG" | jq -r '.AuthType')
    if [[ "$AUTH_TYPE" == "NONE" ]]; then
        pass "Function URL configured with NONE auth type"
    else
        fail "Auth type is '$AUTH_TYPE' (expected 'NONE')"
    fi
else
    fail "Function URL not configured"
fi

# =============================================================================
# Test 3: Direct Lambda invocation
# =============================================================================
echo ""
echo "Test 3: Direct Lambda invocation"

PAYLOAD='{"requestContext":{"http":{"method":"GET","path":"/test"}},"queryStringParameters":{"foo":"bar"}}'
echo "$PAYLOAD" > /tmp/payload.json

INVOKE_RESULT=$($AWS lambda invoke \
    --function-name "$FUNCTION_NAME" \
    --payload "file:///tmp/payload.json" \
    --region "$REGION" \
    /tmp/lambda-response.json 2>&1 || echo "INVOKE_FAILED")

if [[ -f /tmp/lambda-response.json ]]; then
    RESPONSE=$(cat /tmp/lambda-response.json)

    # Check statusCode
    STATUS_CODE=$(echo "$RESPONSE" | jq -r '.statusCode' 2>/dev/null || echo "")
    if [[ "$STATUS_CODE" == "200" ]]; then
        pass "Lambda returned statusCode 200"
    else
        fail "Lambda returned statusCode '$STATUS_CODE' (expected '200')"
    fi

    # Check response body contains expected message
    BODY=$(echo "$RESPONSE" | jq -r '.body' 2>/dev/null | jq -r '.message' 2>/dev/null || echo "")
    if [[ "$BODY" == "Hello from Lambda Function URL!" ]]; then
        pass "Response contains expected message"
    else
        fail "Response message is '$BODY'"
    fi

    # Check that query params were processed
    QUERY_FOO=$(echo "$RESPONSE" | jq -r '.body' 2>/dev/null | jq -r '.request.queryParams.foo' 2>/dev/null || echo "")
    if [[ "$QUERY_FOO" == "bar" ]]; then
        pass "Query parameters processed correctly"
    else
        fail "Query param 'foo' is '$QUERY_FOO' (expected 'bar')"
    fi
else
    fail "Lambda invocation failed: $INVOKE_RESULT"
fi

# =============================================================================
# Test 4: HTTP invocation via Function URL
# =============================================================================
echo ""
echo "Test 4: HTTP invocation via Function URL"

if [[ -n "${FUNCTION_URL:-}" ]]; then
    HTTP_RESPONSE=$(curl -s -X GET "$FUNCTION_URL" 2>/dev/null || echo "")

    if [[ -n "$HTTP_RESPONSE" ]]; then
        HTTP_MESSAGE=$(echo "$HTTP_RESPONSE" | jq -r '.message' 2>/dev/null || echo "")
        if [[ "$HTTP_MESSAGE" == "Hello from Lambda Function URL!" ]]; then
            pass "HTTP GET via Function URL works"
        else
            fail "HTTP response message unexpected: $HTTP_MESSAGE"
        fi
    else
        fail "No response from Function URL"
    fi
else
    echo "  SKIP: Function URL not available"
fi

# =============================================================================
# Test 5: POST request with body
# =============================================================================
echo ""
echo "Test 5: POST request with JSON body"

if [[ -n "${FUNCTION_URL:-}" ]]; then
    POST_BODY='{"name":"LocalStack","version":"3.0"}'
    HTTP_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$POST_BODY" \
        "$FUNCTION_URL" 2>/dev/null || echo "")

    if [[ -n "$HTTP_RESPONSE" ]]; then
        # Check that the body was received and parsed
        RECEIVED_NAME=$(echo "$HTTP_RESPONSE" | jq -r '.request.body.name' 2>/dev/null || echo "")
        if [[ "$RECEIVED_NAME" == "LocalStack" ]]; then
            pass "POST body parsed correctly"
        else
            fail "POST body not parsed correctly: received_name='$RECEIVED_NAME'"
        fi
    else
        fail "No response from POST request"
    fi
else
    echo "  SKIP: Function URL not available"
fi

# =============================================================================
# Cleanup
# =============================================================================
rm -f /tmp/payload.json /tmp/lambda-response.json

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
