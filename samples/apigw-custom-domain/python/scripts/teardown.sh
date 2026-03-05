#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Tearing down API Gateway Custom Domain Sample (scripts)"

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

# Read .env to get resource names
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    source "$SCRIPT_DIR/.env"
fi

DOMAIN_NAME="${DOMAIN_NAME:-api.example.com}"
FUNCTION_NAME="${FUNCTION_NAME:-apigw-custom-domain-handler}"
API_ID="${API_ID:-}"
CERT_ARN="${CERT_ARN:-}"
HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-}"

# Delete API mapping and custom domain
if [[ -n "$DOMAIN_NAME" ]]; then
    echo "Deleting API mapping and custom domain..."
    $AWS apigatewayv2 delete-api-mapping \
        --domain-name "$DOMAIN_NAME" \
        --api-mapping-id "$($AWS apigatewayv2 get-api-mappings --domain-name "$DOMAIN_NAME" --query 'Items[0].ApiMappingId' --output text 2>/dev/null || echo '')" \
        --region "$REGION" 2>/dev/null || true
    $AWS apigatewayv2 delete-domain-name --domain-name "$DOMAIN_NAME" --region "$REGION" 2>/dev/null || true
fi

# Delete API Gateway
if [[ -n "$API_ID" ]]; then
    echo "Deleting API Gateway..."
    $AWS apigatewayv2 delete-api --api-id "$API_ID" --region "$REGION" 2>/dev/null || true
fi

# Delete Lambda function
if [[ -n "$FUNCTION_NAME" ]]; then
    echo "Deleting Lambda function..."
    $AWS lambda delete-function --function-name "$FUNCTION_NAME" --region "$REGION" 2>/dev/null || true
fi

# Delete IAM role
echo "Deleting IAM role..."
$AWS iam delete-role --role-name "apigw-custom-domain-role" --region "$REGION" 2>/dev/null || true

# Delete Route53 record and hosted zone
if [[ -n "$HOSTED_ZONE_ID" ]] && [[ "$HOSTED_ZONE_ID" != "None" ]]; then
    echo "Deleting Route53 resources..."
    $AWS route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "{
            \"Changes\": [{
                \"Action\": \"DELETE\",
                \"ResourceRecordSet\": {
                    \"Name\": \"$DOMAIN_NAME\",
                    \"Type\": \"CNAME\",
                    \"TTL\": 300,
                    \"ResourceRecords\": [{\"Value\": \"placeholder\"}]
                }
            }]
        }" --region "$REGION" 2>/dev/null || true
    $AWS route53 delete-hosted-zone --id "$HOSTED_ZONE_ID" --region "$REGION" 2>/dev/null || true
fi

# Delete ACM certificate
if [[ -n "$CERT_ARN" ]] && [[ "$CERT_ARN" != "None" ]]; then
    echo "Deleting ACM certificate..."
    $AWS acm delete-certificate --certificate-arn "$CERT_ARN" --region "$REGION" 2>/dev/null || true
fi

# Clean up .env
rm -f "$SCRIPT_DIR/.env"

echo "Teardown complete!"
