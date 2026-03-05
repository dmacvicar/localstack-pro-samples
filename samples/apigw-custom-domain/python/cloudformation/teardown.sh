#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="apigw-custom-domain-stack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
DOMAIN_NAME="api.example.com"

echo "Tearing down API Gateway Custom Domain Sample (cloudformation)"

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

# Delete CloudFormation stack
echo "Deleting CloudFormation stack..."
$AWS cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
$AWS cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true

# Delete ACM certificate (created outside stack)
echo "Deleting ACM certificate..."
CERT_ARN=$($AWS acm list-certificates \
    --region "$REGION" \
    --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn | [0]" \
    --output text 2>/dev/null || echo "")
if [[ -n "$CERT_ARN" ]] && [[ "$CERT_ARN" != "None" ]]; then
    $AWS acm delete-certificate --certificate-arn "$CERT_ARN" --region "$REGION" 2>/dev/null || true
fi

# Clean up .env
rm -f "$PROJECT_DIR/scripts/.env"

echo "Teardown complete!"
