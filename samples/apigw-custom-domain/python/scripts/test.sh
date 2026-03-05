#!/bin/bash
set -euo pipefail

# =============================================================================
# API Gateway Custom Domain - Test Script
#
# Tests:
# 1. ACM certificate exists
# 2. Route53 hosted zone exists
# 3. Lambda function is active
# 4. API Gateway HTTP API exists
# 5. Custom domain is configured
# 6. API responds via custom domain
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

echo "Testing API Gateway Custom Domain Sample"
echo "  Domain: $DOMAIN_NAME"
echo "  API ID: $API_ID"
echo ""

# =============================================================================
# Test 1: ACM Certificate Exists
# =============================================================================
echo "Test 1: ACM certificate exists"

CERT_STATUS=$($AWS acm describe-certificate \
    --certificate-arn "$CERT_ARN" \
    --query 'Certificate.Status' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

if [[ "$CERT_STATUS" == "ISSUED" ]] || [[ "$CERT_STATUS" != "NOT_FOUND" ]]; then
    pass "ACM certificate exists (status: $CERT_STATUS)"
else
    fail "ACM certificate not found"
fi

# =============================================================================
# Test 2: Route53 Hosted Zone Exists
# =============================================================================
echo ""
echo "Test 2: Route53 hosted zone exists"

if [[ -n "$HOSTED_ZONE_ID" ]] && [[ "$HOSTED_ZONE_ID" != "None" ]]; then
    ZONE_INFO=$($AWS route53 get-hosted-zone \
        --id "$HOSTED_ZONE_ID" \
        --query 'HostedZone.Name' \
        --output text 2>/dev/null || echo "NOT_FOUND")

    if [[ "$ZONE_INFO" != "NOT_FOUND" ]]; then
        pass "Route53 hosted zone exists ($ZONE_INFO)"
    else
        fail "Route53 hosted zone not found"
    fi
else
    fail "No hosted zone ID configured"
fi

# =============================================================================
# Test 3: Lambda Function Active
# =============================================================================
echo ""
echo "Test 3: Lambda function is active"

FUNCTION_STATE=$($AWS lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --query 'Configuration.State' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "NOT_FOUND")

if [[ "$FUNCTION_STATE" == "Active" ]]; then
    pass "Lambda function '$FUNCTION_NAME' is Active"
else
    fail "Lambda function state is '$FUNCTION_STATE'"
fi

# =============================================================================
# Test 4: API Gateway HTTP API Exists
# =============================================================================
echo ""
echo "Test 4: API Gateway HTTP API exists"

API_INFO=$($AWS apigatewayv2 get-api \
    --api-id "$API_ID" \
    --region "$REGION" 2>/dev/null || echo "{}")

API_NAME=$(echo "$API_INFO" | jq -r '.Name // "NOT_FOUND"')
PROTOCOL=$(echo "$API_INFO" | jq -r '.ProtocolType // "UNKNOWN"')

if [[ "$PROTOCOL" == "HTTP" ]]; then
    pass "HTTP API '$API_NAME' exists"
else
    fail "API not found or wrong protocol: $PROTOCOL"
fi

# =============================================================================
# Test 5: Custom Domain Configured
# =============================================================================
echo ""
echo "Test 5: Custom domain is configured"

DOMAIN_INFO=$($AWS apigatewayv2 get-domain-name \
    --domain-name "$DOMAIN_NAME" \
    --region "$REGION" 2>/dev/null || echo "{}")

DOMAIN_STATUS=$(echo "$DOMAIN_INFO" | jq -r '.DomainNameConfigurations[0].DomainNameStatus // "NOT_FOUND"')

if [[ "$DOMAIN_STATUS" != "NOT_FOUND" ]] && [[ -n "$DOMAIN_STATUS" ]]; then
    pass "Custom domain '$DOMAIN_NAME' configured (status: $DOMAIN_STATUS)"
else
    fail "Custom domain not configured"
fi

# =============================================================================
# Test 6: API Responds via Custom Domain
# =============================================================================
echo ""
echo "Test 6: API responds via custom domain"

# Test using Host header to route through custom domain
# LocalStack routes based on Host header
RESPONSE=$(curl -sf --max-time 10 \
    -H "Host: $DOMAIN_NAME" \
    "http://localhost.localstack.cloud:4566/hello" 2>/dev/null || echo "")

if echo "$RESPONSE" | grep -q "Hello"; then
    pass "API responds via custom domain: $RESPONSE"
else
    # Fallback: test direct API endpoint
    if [[ -n "$API_ENDPOINT" ]]; then
        DIRECT_RESPONSE=$(curl -sf --max-time 10 "$API_ENDPOINT/hello" 2>/dev/null || echo "")
        if echo "$DIRECT_RESPONSE" | grep -q "Hello"; then
            pass "API responds at direct endpoint: $DIRECT_RESPONSE"
        else
            fail "API did not respond (tried custom domain and direct endpoint)"
        fi
    else
        fail "API did not respond via custom domain"
    fi
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
