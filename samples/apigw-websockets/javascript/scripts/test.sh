#!/bin/bash
set -euo pipefail

# =============================================================================
# API Gateway WebSockets - Test Script
#
# Tests:
# 1. WebSocket API exists
# 2. Lambda functions are active
# 3. Routes are configured
# 4. WebSocket connection and message round-trip
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

echo "Testing API Gateway WebSockets Sample"
echo "  API ID: $WS_API_ID"
echo "  Endpoint: $WS_ENDPOINT"
echo ""

# =============================================================================
# Test 1: WebSocket API exists
# =============================================================================
echo "Test 1: WebSocket API exists"

API_INFO=$($AWS apigatewayv2 get-api \
    --api-id "$WS_API_ID" \
    --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

API_NAME=$(echo "$API_INFO" | jq -r '.Name // "NOT_FOUND"')
PROTOCOL=$(echo "$API_INFO" | jq -r '.ProtocolType // "UNKNOWN"')

if [[ "$PROTOCOL" == "WEBSOCKET" ]] && echo "$API_NAME" | grep -q "apigw-websockets-sample"; then
    pass "WebSocket API '$API_NAME' exists (Protocol: $PROTOCOL)"
else
    fail "WebSocket API not found or wrong protocol (got: $API_NAME, protocol: $PROTOCOL)"
fi

# =============================================================================
# Test 2: Lambda functions are active
# =============================================================================
echo ""
echo "Test 2: Lambda functions are active"

for FUNC in connectionHandler defaultHandler actionHandler; do
    FUNCTION_NAME="apigw-websockets-sample-$STAGE-$FUNC"
    FUNCTION_STATE=$($AWS lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --query 'Configuration.State' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

    if [[ "$FUNCTION_STATE" == "Active" ]]; then
        pass "Function '$FUNC' is Active"
    else
        fail "Function '$FUNC' state is '$FUNCTION_STATE'"
    fi
done

# =============================================================================
# Test 3: Routes are configured
# =============================================================================
echo ""
echo "Test 3: Routes are configured"

ROUTES=$($AWS apigatewayv2 get-routes \
    --api-id "$WS_API_ID" \
    --query 'Items[].RouteKey' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

for EXPECTED_ROUTE in '$connect' '$disconnect' '$default' 'test-action'; do
    if echo "$ROUTES" | grep -q "$EXPECTED_ROUTE"; then
        pass "Route '$EXPECTED_ROUTE' exists"
    else
        fail "Route '$EXPECTED_ROUTE' not found"
    fi
done

# =============================================================================
# Test 4: WebSocket connection test (using wscat or Python)
# =============================================================================
echo ""
echo "Test 4: WebSocket connection and message round-trip"

# Use Python with uv to test WebSocket
PYTHON_TEST=$(cat << 'PYEOF'
import sys
import json
import asyncio
import websockets

async def test_websocket(url):
    try:
        async with websockets.connect(url, close_timeout=5, open_timeout=5) as ws:
            # Send a test message
            msg = {"action": "test-action", "data": "hello"}
            await ws.send(json.dumps(msg))

            # Wait for response
            response = await asyncio.wait_for(ws.recv(), timeout=5)
            result = json.loads(response)

            # Verify we got a response - check for our data or requestContext
            if result.get("data") == "hello" or result.get("requestContext", {}).get("routeKey") == "test-action":
                print("SUCCESS")
                return True
            else:
                print(f"UNEXPECTED: {result}")
                return False
    except Exception as e:
        print(f"ERROR: {e}")
        return False

url = sys.argv[1]
result = asyncio.run(test_websocket(url))
sys.exit(0 if result else 1)
PYEOF
)

# Run Python WebSocket test using uv
WS_RESULT=$(uv run --with websockets python -c "$PYTHON_TEST" "$WS_ENDPOINT" 2>&1)

case "$WS_RESULT" in
    SUCCESS)
        pass "WebSocket message round-trip successful"
        ;;
    SKIP*)
        echo "  SKIP: $WS_RESULT"
        ;;
    *)
        fail "WebSocket test: $WS_RESULT"
        ;;
esac

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
