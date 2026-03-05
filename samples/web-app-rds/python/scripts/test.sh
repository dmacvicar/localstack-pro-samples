#!/bin/bash
set -euo pipefail

# =============================================================================
# Web App RDS - Test Script
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

echo "Testing Web App RDS"
echo "  RDS Instance: $DB_INSTANCE_ID"
echo "  Function: $FUNCTION_NAME"

# Helper function to invoke Lambda
invoke_lambda() {
    local payload="$1"
    echo "$payload" > /tmp/payload.json
    $AWS lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --payload "file:///tmp/payload.json" \
        --region "$REGION" \
        /tmp/response.json > /dev/null 2>&1
    cat /tmp/response.json
}

# Test 1: Health check
echo ""
echo "Test 1: Health check"
PAYLOAD='{"httpMethod": "GET", "path": "/health"}'

RESPONSE=$(invoke_lambda "$PAYLOAD")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | jq -e '.statusCode == 200' > /dev/null 2>&1; then
    echo "PASS: Health check passed"
else
    echo "FAIL: Health check failed"
    exit 1
fi

# Test 2: Create an item
echo ""
echo "Test 2: Create an item"
PAYLOAD=$(cat << 'EOF'
{
    "httpMethod": "POST",
    "path": "/items",
    "body": "{\"id\": \"item-001\", \"name\": \"Database Product\", \"category\": \"software\", \"price\": 199.99}"
}
EOF
)

RESPONSE=$(invoke_lambda "$PAYLOAD")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | jq -e '.statusCode == 201' > /dev/null 2>&1; then
    echo "PASS: Item created"
else
    echo "FAIL: Expected statusCode 201"
    exit 1
fi

# Test 3: Get the item
echo ""
echo "Test 3: Get the item"
PAYLOAD='{"httpMethod": "GET", "path": "/items/item-001", "pathParameters": {"id": "item-001"}}'

RESPONSE=$(invoke_lambda "$PAYLOAD")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | jq -e '.statusCode == 200' > /dev/null 2>&1; then
    BODY=$(echo "$RESPONSE" | jq -r '.body')
    NAME=$(echo "$BODY" | jq -r '.name')
    if [[ "$NAME" == "Database Product" ]]; then
        echo "PASS: Got correct item"
    else
        echo "FAIL: Item name mismatch"
        exit 1
    fi
else
    echo "FAIL: Expected statusCode 200"
    exit 1
fi

# Test 4: Update the item
echo ""
echo "Test 4: Update the item"
PAYLOAD=$(cat << 'EOF'
{
    "httpMethod": "PUT",
    "path": "/items/item-001",
    "pathParameters": {"id": "item-001"},
    "body": "{\"name\": \"Updated Database Product\", \"price\": 249.99}"
}
EOF
)

RESPONSE=$(invoke_lambda "$PAYLOAD")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | jq -e '.statusCode == 200' > /dev/null 2>&1; then
    echo "PASS: Item updated"
else
    echo "FAIL: Expected statusCode 200"
    exit 1
fi

# Test 5: List items
echo ""
echo "Test 5: List items"
PAYLOAD='{"httpMethod": "GET", "path": "/items"}'

RESPONSE=$(invoke_lambda "$PAYLOAD")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | jq -e '.statusCode == 200' > /dev/null 2>&1; then
    echo "PASS: Listed items"
else
    echo "FAIL: Expected statusCode 200"
    exit 1
fi

# Test 6: Delete the item
echo ""
echo "Test 6: Delete the item"
PAYLOAD='{"httpMethod": "DELETE", "path": "/items/item-001", "pathParameters": {"id": "item-001"}}'

RESPONSE=$(invoke_lambda "$PAYLOAD")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | jq -e '.statusCode == 204' > /dev/null 2>&1; then
    echo "PASS: Item deleted"
else
    echo "FAIL: Expected statusCode 204"
    exit 1
fi

# Cleanup
rm -f /tmp/response.json

echo ""
echo "SUCCESS: Web App RDS tests passed!"
