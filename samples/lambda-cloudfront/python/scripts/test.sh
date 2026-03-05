#!/bin/bash
set -euo pipefail

# =============================================================================
# Lambda CloudFront - Test Script
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

echo "Testing Lambda CloudFront Sample"
echo "  Function: $FUNCTION_NAME"

# Test 1: Direct Lambda invocation
echo ""
echo "Test 1: Direct Lambda invocation"
PAYLOAD='{"httpMethod": "GET", "path": "/test"}'
echo "$PAYLOAD" > /tmp/payload.json

RESPONSE=$($AWS lambda invoke \
    --function-name "$FUNCTION_NAME" \
    --payload "file:///tmp/payload.json" \
    --region "$REGION" \
    /tmp/lambda-response.json 2>&1)

echo "Response:"
cat /tmp/lambda-response.json | jq . 2>/dev/null || cat /tmp/lambda-response.json

if jq -e '.statusCode == 200' /tmp/lambda-response.json > /dev/null 2>&1; then
    echo "PASS: Lambda returned 200"
else
    echo "FAIL: Expected statusCode 200"
    rm -f /tmp/lambda-response.json /tmp/payload.json
    exit 1
fi

# Test 2: Function URL (if available)
if [[ -n "${FUNCTION_URL:-}" ]]; then
    echo ""
    echo "Test 2: Lambda Function URL"
    RESPONSE=$(curl -s "$FUNCTION_URL" 2>/dev/null || echo "")

    if [[ -n "$RESPONSE" ]]; then
        echo "Response: $RESPONSE"
        if echo "$RESPONSE" | jq -e '.message' > /dev/null 2>&1; then
            echo "PASS: Function URL responded with message"
        else
            echo "WARNING: Function URL response unexpected format"
        fi
    else
        echo "WARNING: Function URL not responding"
    fi
fi

# Cleanup
rm -f /tmp/lambda-response.json /tmp/payload.json

echo ""
echo "SUCCESS: Lambda CloudFront tests passed!"
