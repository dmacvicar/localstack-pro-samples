#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="ApiGwCustomDomainStack"
DOMAIN_NAME="api.example.com"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Tearing down API Gateway Custom Domain Sample (cdk)"

cd "$SCRIPT_DIR"

if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    CDK="cdk"
fi

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

# Destroy CDK stack
$CDK destroy --force 2>/dev/null || true

# Delete ACM certificate (created outside stack)
echo "Deleting ACM certificate..."
CERT_ARN=$($AWS acm list-certificates \
    --region "$REGION" \
    --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn | [0]" \
    --output text 2>/dev/null || echo "")
if [[ -n "$CERT_ARN" ]] && [[ "$CERT_ARN" != "None" ]]; then
    $AWS acm delete-certificate --certificate-arn "$CERT_ARN" --region "$REGION" 2>/dev/null || true
fi

# Clean up outputs
rm -f cdk-outputs.json
rm -rf cdk.out

# Clean up .env
rm -f "$PROJECT_DIR/scripts/.env"

echo "Teardown complete!"
