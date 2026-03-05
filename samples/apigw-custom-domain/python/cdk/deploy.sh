#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="ApiGwCustomDomainStack"
DOMAIN_NAME="api.example.com"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying API Gateway Custom Domain Sample via CDK"
echo "  Stack: $STACK_NAME"
echo "  Region: $REGION"

cd "$SCRIPT_DIR"

# Determine CDK CLI to use
if command -v cdklocal &> /dev/null; then
    CDK="cdklocal"
else
    echo "Warning: cdklocal not found, using cdk (may not work with LocalStack)"
    CDK="cdk"
fi

AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"

# Step 1: Generate and import certificate
echo ""
echo "Step 1: Setting up ACM certificate..."

CERT_DIR="$PROJECT_DIR/certs"
mkdir -p "$CERT_DIR"

if [[ ! -f "$CERT_DIR/server.key" ]]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt" \
        -subj "/CN=$DOMAIN_NAME/O=LocalStack Sample/C=US" \
        2>/dev/null
fi

CERT_ARN=$($AWS acm import-certificate \
    --certificate "fileb://$CERT_DIR/server.crt" \
    --private-key "fileb://$CERT_DIR/server.key" \
    --region "$REGION" \
    --query 'CertificateArn' \
    --output text 2>/dev/null || echo "")

if [[ -z "$CERT_ARN" ]]; then
    CERT_ARN=$($AWS acm list-certificates \
        --region "$REGION" \
        --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn | [0]" \
        --output text 2>/dev/null || echo "")
fi

echo "  Certificate ARN: $CERT_ARN"

# Step 2: Install CDK dependencies
echo ""
echo "Step 2: Installing CDK dependencies..."
uv pip install --system -r requirements.txt --quiet 2>/dev/null || true

# Step 3: Bootstrap CDK
echo "Step 3: Bootstrapping CDK..."
$CDK bootstrap --quiet 2>/dev/null || true

# Step 4: Deploy stack
echo "Step 4: Deploying CDK stack..."
$CDK deploy --require-approval never --outputs-file cdk-outputs.json \
    --context cert_arn="$CERT_ARN"

# Extract outputs
echo "Step 5: Extracting outputs..."
FUNCTION_NAME=$(jq -r ".$STACK_NAME.FunctionName" cdk-outputs.json)
API_ID=$(jq -r ".$STACK_NAME.ApiId" cdk-outputs.json)
API_ENDPOINT=$(jq -r ".$STACK_NAME.ApiEndpoint" cdk-outputs.json)
HOSTED_ZONE_ID=$(jq -r ".$STACK_NAME.HostedZoneId" cdk-outputs.json)

# Save config for test script
cat > "$PROJECT_DIR/scripts/.env" << EOF
FUNCTION_NAME=$FUNCTION_NAME
API_ID=$API_ID
API_ENDPOINT=$API_ENDPOINT
DOMAIN_NAME=$DOMAIN_NAME
CERT_ARN=$CERT_ARN
HOSTED_ZONE_ID=$HOSTED_ZONE_ID
REGION=$REGION
STACK_NAME=$STACK_NAME
EOF

echo ""
echo "Deployment complete!"
echo "  Function Name: $FUNCTION_NAME"
echo "  API ID: $API_ID"
echo "  API Endpoint: $API_ENDPOINT"
echo "  Domain: $DOMAIN_NAME"
