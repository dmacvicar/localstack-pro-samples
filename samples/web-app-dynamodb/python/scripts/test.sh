#!/bin/bash
set -euo pipefail

# =============================================================================
# Web App DynamoDB - Test Script
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

echo "Testing Web App DynamoDB"
echo "  Table: $TABLE_NAME"
echo "  Function: $FUNCTION_NAME"

# Helper function to invoke Lambda
invoke_lambda() {
    local payload="$1"
    # Write payload to temp file to avoid escaping issues
    echo "$payload" > /tmp/payload.json
    $AWS lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --payload "file:///tmp/payload.json" \
        --region "$REGION" \
        /tmp/response.json > /dev/null 2>&1
    cat /tmp/response.json
}

# Test 1: Create an item
echo ""
echo "Test 1: Create an item"
PAYLOAD=$(cat << 'EOF'
{
    "httpMethod": "POST",
    "path": "/items",
    "body": "{\"id\": \"item-001\", \"name\": \"Test Product\", \"category\": \"electronics\", \"price\": 99.99}"
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

# Test 2: Get the item
echo ""
echo "Test 2: Get the item"
PAYLOAD='{"httpMethod": "GET", "path": "/items/item-001", "pathParameters": {"id": "item-001"}}'

RESPONSE=$(invoke_lambda "$PAYLOAD")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | jq -e '.statusCode == 200' > /dev/null 2>&1; then
    BODY=$(echo "$RESPONSE" | jq -r '.body')
    NAME=$(echo "$BODY" | jq -r '.name')
    if [[ "$NAME" == "Test Product" ]]; then
        echo "PASS: Got correct item"
    else
        echo "FAIL: Item name mismatch"
        exit 1
    fi
else
    echo "FAIL: Expected statusCode 200"
    exit 1
fi

# Test 3: Update the item
echo ""
echo "Test 3: Update the item"
PAYLOAD=$(cat << 'EOF'
{
    "httpMethod": "PUT",
    "path": "/items/item-001",
    "pathParameters": {"id": "item-001"},
    "body": "{\"name\": \"Updated Product\", \"price\": 149.99}"
}
EOF
)

RESPONSE=$(invoke_lambda "$PAYLOAD")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | jq -e '.statusCode == 200' > /dev/null 2>&1; then
    BODY=$(echo "$RESPONSE" | jq -r '.body')
    NAME=$(echo "$BODY" | jq -r '.name')
    if [[ "$NAME" == "Updated Product" ]]; then
        echo "PASS: Item updated"
    else
        echo "FAIL: Item not updated correctly"
        exit 1
    fi
else
    echo "FAIL: Expected statusCode 200"
    exit 1
fi

# Test 4: List items
echo ""
echo "Test 4: List items"
PAYLOAD='{"httpMethod": "GET", "path": "/items"}'

RESPONSE=$(invoke_lambda "$PAYLOAD")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | jq -e '.statusCode == 200' > /dev/null 2>&1; then
    BODY=$(echo "$RESPONSE" | jq -r '.body')
    COUNT=$(echo "$BODY" | jq '.items | length')
    if [[ "$COUNT" -ge 1 ]]; then
        echo "PASS: Listed $COUNT items"
    else
        echo "FAIL: Expected at least 1 item"
        exit 1
    fi
else
    echo "FAIL: Expected statusCode 200"
    exit 1
fi

# Test 5: Delete the item
echo ""
echo "Test 5: Delete the item"
PAYLOAD='{"httpMethod": "DELETE", "path": "/items/item-001", "pathParameters": {"id": "item-001"}}'

RESPONSE=$(invoke_lambda "$PAYLOAD")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | jq -e '.statusCode == 204' > /dev/null 2>&1; then
    echo "PASS: Item deleted"
else
    echo "FAIL: Expected statusCode 204"
    exit 1
fi

# Test 6: Verify item is deleted
echo ""
echo "Test 6: Verify item is deleted"
PAYLOAD='{"httpMethod": "GET", "path": "/items/item-001", "pathParameters": {"id": "item-001"}}'

RESPONSE=$(invoke_lambda "$PAYLOAD")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | jq -e '.statusCode == 404' > /dev/null 2>&1; then
    echo "PASS: Item correctly not found"
else
    echo "FAIL: Expected statusCode 404"
    exit 1
fi

# Cleanup
rm -f /tmp/response.json

echo ""
echo "SUCCESS: Web App DynamoDB tests passed!"
