#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STACK_NAME="apigw-custom-domain-stack"
FUNCTION_NAME="apigw-custom-domain-cfn"
DOMAIN_NAME="api.example.com"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "Deploying API Gateway Custom Domain Sample via CloudFormation"
echo "  Stack: $STACK_NAME"
echo "  Region: $REGION"

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
        --output text 2>/dev/null || echo "arn:aws:acm:$REGION:000000000000:certificate/placeholder")
fi

echo "  Certificate ARN: $CERT_ARN"

# Step 2: Deploy CloudFormation stack
echo ""
echo "Step 2: Deploying CloudFormation stack..."
cd "$SCRIPT_DIR"

$AWS cloudformation deploy \
    --stack-name "$STACK_NAME" \
    --template-file template.yml \
    --parameter-overrides \
        "FunctionName=$FUNCTION_NAME" \
        "DomainName=$DOMAIN_NAME" \
        "CertificateArn=$CERT_ARN" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --no-fail-on-empty-changeset

# Wait for stack to complete
echo "Step 3: Waiting for stack to complete..."
$AWS cloudformation wait stack-create-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION" 2>/dev/null || \
$AWS cloudformation wait stack-update-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION" 2>/dev/null || true

# Extract outputs
echo "Step 4: Extracting outputs..."
STACK_OUTPUTS=$($AWS cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs' \
    --region "$REGION" 2>/dev/null)

FUNCTION_NAME=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionName") | .OutputValue')
API_ID=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="ApiId") | .OutputValue')
API_ENDPOINT=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="ApiEndpoint") | .OutputValue')
HOSTED_ZONE_ID=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="HostedZoneId") | .OutputValue')

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
