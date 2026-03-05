#!/bin/bash
set -euo pipefail

# =============================================================================
# API Gateway Custom Domain - Deploy Script
#
# Demonstrates API Gateway HTTP API with custom domain name using:
# - ACM for SSL/TLS certificates
# - Route53 for DNS
# - API Gateway v2 custom domain mapping
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
DOMAIN_NAME="api.example.com"

echo "Deploying API Gateway Custom Domain Sample"
echo "  Region: $REGION"
echo "  Domain: $DOMAIN_NAME"
echo ""

# Determine CLI to use
if command -v awslocal &> /dev/null; then
    AWS="awslocal"
else
    AWS="aws --endpoint-url=http://localhost.localstack.cloud:4566"
fi

# =============================================================================
# Step 1: Generate Self-Signed Certificate
# =============================================================================
echo "Step 1: Generating SSL certificate..."

CERT_DIR="$PROJECT_DIR/certs"
mkdir -p "$CERT_DIR"

# Generate private key and self-signed certificate
if [[ ! -f "$CERT_DIR/server.key" ]]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt" \
        -subj "/CN=$DOMAIN_NAME/O=LocalStack Sample/C=US" \
        2>/dev/null
    echo "  Certificate generated"
else
    echo "  Certificate already exists"
fi

# =============================================================================
# Step 2: Import Certificate to ACM
# =============================================================================
echo ""
echo "Step 2: Importing certificate to ACM..."

CERT_ARN=$($AWS acm import-certificate \
    --certificate "fileb://$CERT_DIR/server.crt" \
    --private-key "fileb://$CERT_DIR/server.key" \
    --region "$REGION" \
    --query 'CertificateArn' \
    --output text 2>/dev/null || echo "")

if [[ -z "$CERT_ARN" ]]; then
    # Certificate might already exist, list and find it
    CERT_ARN=$($AWS acm list-certificates \
        --region "$REGION" \
        --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn | [0]" \
        --output text 2>/dev/null || echo "")
fi

if [[ -z "$CERT_ARN" ]] || [[ "$CERT_ARN" == "None" ]]; then
    echo "  Warning: Could not import or find certificate"
    CERT_ARN="arn:aws:acm:$REGION:000000000000:certificate/placeholder"
fi

echo "  Certificate ARN: $CERT_ARN"

# =============================================================================
# Step 3: Create Route53 Hosted Zone
# =============================================================================
echo ""
echo "Step 3: Creating Route53 hosted zone..."

HOSTED_ZONE_ID=$($AWS route53 list-hosted-zones-by-name \
    --dns-name "example.com" \
    --query "HostedZones[?Name=='example.com.'].Id | [0]" \
    --output text 2>/dev/null || echo "")

if [[ -z "$HOSTED_ZONE_ID" ]] || [[ "$HOSTED_ZONE_ID" == "None" ]]; then
    HOSTED_ZONE_ID=$($AWS route53 create-hosted-zone \
        --name "example.com" \
        --caller-reference "apigw-custom-domain-$(date +%s)" \
        --query 'HostedZone.Id' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
fi

# Clean up the ID (remove /hostedzone/ prefix if present)
HOSTED_ZONE_ID="${HOSTED_ZONE_ID##*/}"
echo "  Hosted Zone ID: $HOSTED_ZONE_ID"

# =============================================================================
# Step 4: Create Lambda Function
# =============================================================================
echo ""
echo "Step 4: Creating Lambda function..."

FUNCTION_NAME="apigw-custom-domain-handler"
ROLE_NAME="apigw-custom-domain-role"

# Create IAM role
ROLE_ARN=$($AWS iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }' \
    --query 'Role.Arn' \
    --output text \
    --region "$REGION" 2>/dev/null || \
    $AWS iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text --region "$REGION" 2>/dev/null)

echo "  Role ARN: $ROLE_ARN"

# Package Lambda code
cd "$PROJECT_DIR"
zip -j /tmp/apigw-custom-domain.zip handler.py > /dev/null 2>&1

# Create or update Lambda function
LAMBDA_ARN=$($AWS lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime python3.11 \
    --handler handler.hello \
    --role "$ROLE_ARN" \
    --zip-file "fileb:///tmp/apigw-custom-domain.zip" \
    --query 'FunctionArn' \
    --output text \
    --region "$REGION" 2>/dev/null || \
    $AWS lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --zip-file "fileb:///tmp/apigw-custom-domain.zip" \
        --query 'FunctionArn' \
        --output text \
        --region "$REGION" 2>/dev/null)

echo "  Lambda ARN: $LAMBDA_ARN"

# Wait for function to be active
echo "  Waiting for function to be active..."
for i in {1..30}; do
    STATE=$($AWS lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --query 'Configuration.State' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "Pending")
    if [[ "$STATE" == "Active" ]]; then
        echo "  Function is active"
        break
    fi
    sleep 1
done

# =============================================================================
# Step 5: Create API Gateway HTTP API
# =============================================================================
echo ""
echo "Step 5: Creating API Gateway HTTP API..."

API_ID=$($AWS apigatewayv2 create-api \
    --name "apigw-custom-domain-api" \
    --protocol-type HTTP \
    --query 'ApiId' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

if [[ -z "$API_ID" ]]; then
    # API might exist, find it
    API_ID=$($AWS apigatewayv2 get-apis \
        --query "Items[?Name=='apigw-custom-domain-api'].ApiId | [0]" \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
fi

echo "  API ID: $API_ID"

# Create Lambda integration
INTEGRATION_ID=$($AWS apigatewayv2 create-integration \
    --api-id "$API_ID" \
    --integration-type AWS_PROXY \
    --integration-uri "$LAMBDA_ARN" \
    --payload-format-version "2.0" \
    --query 'IntegrationId' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

echo "  Integration ID: $INTEGRATION_ID"

# Create routes
$AWS apigatewayv2 create-route \
    --api-id "$API_ID" \
    --route-key "GET /hello" \
    --target "integrations/$INTEGRATION_ID" \
    --region "$REGION" > /dev/null 2>&1 || true

$AWS apigatewayv2 create-route \
    --api-id "$API_ID" \
    --route-key "GET /goodbye" \
    --target "integrations/$INTEGRATION_ID" \
    --region "$REGION" > /dev/null 2>&1 || true

echo "  Routes created: /hello, /goodbye"

# Create default stage
$AWS apigatewayv2 create-stage \
    --api-id "$API_ID" \
    --stage-name '$default' \
    --auto-deploy \
    --region "$REGION" > /dev/null 2>&1 || true

# Add Lambda permission for API Gateway
$AWS lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --statement-id "apigw-invoke-$(date +%s)" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:000000000000:$API_ID/*" \
    --region "$REGION" > /dev/null 2>&1 || true

# =============================================================================
# Step 6: Create Custom Domain
# =============================================================================
echo ""
echo "Step 6: Creating custom domain..."

DOMAIN_RESULT=$($AWS apigatewayv2 create-domain-name \
    --domain-name "$DOMAIN_NAME" \
    --domain-name-configurations "CertificateArn=$CERT_ARN,EndpointType=REGIONAL" \
    --region "$REGION" 2>/dev/null || echo "{}")

DOMAIN_TARGET=$(echo "$DOMAIN_RESULT" | jq -r '.DomainNameConfigurations[0].ApiGatewayDomainName // empty')

if [[ -z "$DOMAIN_TARGET" ]]; then
    # Domain might exist
    DOMAIN_TARGET=$($AWS apigatewayv2 get-domain-name \
        --domain-name "$DOMAIN_NAME" \
        --query 'DomainNameConfigurations[0].ApiGatewayDomainName' \
        --output text \
        --region "$REGION" 2>/dev/null || echo "")
fi

echo "  Domain target: $DOMAIN_TARGET"

# Create API mapping
$AWS apigatewayv2 create-api-mapping \
    --domain-name "$DOMAIN_NAME" \
    --api-id "$API_ID" \
    --stage '$default' \
    --region "$REGION" > /dev/null 2>&1 || true

echo "  API mapping created"

# =============================================================================
# Step 7: Create Route53 Record
# =============================================================================
echo ""
echo "Step 7: Creating Route53 DNS record..."

if [[ -n "$HOSTED_ZONE_ID" ]] && [[ -n "$DOMAIN_TARGET" ]]; then
    $AWS route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "{
            \"Changes\": [{
                \"Action\": \"UPSERT\",
                \"ResourceRecordSet\": {
                    \"Name\": \"$DOMAIN_NAME\",
                    \"Type\": \"CNAME\",
                    \"TTL\": 300,
                    \"ResourceRecords\": [{\"Value\": \"$DOMAIN_TARGET\"}]
                }
            }]
        }" \
        --region "$REGION" > /dev/null 2>&1 || true
    echo "  DNS record created"
else
    echo "  Skipped DNS record (missing zone or target)"
fi

# =============================================================================
# Get API Endpoint
# =============================================================================
API_ENDPOINT=$($AWS apigatewayv2 get-api \
    --api-id "$API_ID" \
    --query 'ApiEndpoint' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

# =============================================================================
# Save Configuration
# =============================================================================
cat > "$SCRIPT_DIR/.env" << EOF
REGION=$REGION
DOMAIN_NAME=$DOMAIN_NAME
CERT_ARN=$CERT_ARN
HOSTED_ZONE_ID=$HOSTED_ZONE_ID
FUNCTION_NAME=$FUNCTION_NAME
API_ID=$API_ID
API_ENDPOINT=$API_ENDPOINT
EOF

echo ""
echo "Deployment complete!"
echo "  Domain: $DOMAIN_NAME"
echo "  API ID: $API_ID"
echo "  API Endpoint: $API_ENDPOINT"
echo ""
echo "Test with:"
echo "  curl -H 'Host: $DOMAIN_NAME' $API_ENDPOINT/hello"
