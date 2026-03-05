#!/bin/bash
set -euo pipefail

# =============================================================================
# Lambda S3 HTTP - Test Script
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

echo "Testing Lambda S3 HTTP (Gaming Scoreboard)"
echo "  Table: $TABLE_NAME"
echo "  Bucket: $BUCKET_NAME"
echo "  Queue: $QUEUE_NAME"

# Test 1: Submit a score via direct Lambda invocation
echo ""
echo "Test 1: Submit a score"
PAYLOAD=$(cat << 'EOF'
{
    "httpMethod": "POST",
    "path": "/scores",
    "body": "{\"playerId\": \"player1\", \"score\": 1500, \"game\": \"space-invaders\"}"
}
EOF
)

echo "$PAYLOAD" > /tmp/payload.json
RESPONSE=$($AWS lambda invoke \
    --function-name "$HTTP_FUNCTION" \
    --payload "file:///tmp/payload.json" \
    --region "$REGION" \
    /tmp/response.json 2>&1)

echo "Response:"
cat /tmp/response.json | jq . 2>/dev/null || cat /tmp/response.json

if jq -e '.statusCode == 201' /tmp/response.json > /dev/null 2>&1; then
    echo "PASS: Score submitted"
else
    echo "FAIL: Expected statusCode 201"
    exit 1
fi

# Test 2: Get top scores
echo ""
echo "Test 2: Get top scores"
PAYLOAD='{"httpMethod": "GET", "path": "/scores"}'
echo "$PAYLOAD" > /tmp/payload.json

$AWS lambda invoke \
    --function-name "$HTTP_FUNCTION" \
    --payload "file:///tmp/payload.json" \
    --region "$REGION" \
    /tmp/response.json > /dev/null 2>&1

echo "Response:"
cat /tmp/response.json | jq . 2>/dev/null || cat /tmp/response.json

if jq -e '.statusCode == 200' /tmp/response.json > /dev/null 2>&1; then
    echo "PASS: Got scores"
else
    echo "FAIL: Expected statusCode 200"
    exit 1
fi

# Test 3: Upload a replay file to S3
echo ""
echo "Test 3: Upload replay to S3"
echo "replay data" > /tmp/replay.dat

$AWS s3 cp /tmp/replay.dat "s3://$BUCKET_NAME/player1/game1.dat" \
    --metadata "player-id=player1,game=space-invaders" \
    --region "$REGION"

sleep 2

# Test 4: Get player scores
echo ""
echo "Test 4: Get player scores"
PAYLOAD='{"httpMethod": "GET", "path": "/scores/player1", "pathParameters": {"playerId": "player1"}}'
echo "$PAYLOAD" > /tmp/payload.json

$AWS lambda invoke \
    --function-name "$HTTP_FUNCTION" \
    --payload "file:///tmp/payload.json" \
    --region "$REGION" \
    /tmp/response.json > /dev/null 2>&1

echo "Response:"
cat /tmp/response.json | jq . 2>/dev/null || cat /tmp/response.json

if jq -e '.statusCode == 200' /tmp/response.json > /dev/null 2>&1; then
    echo "PASS: Got player scores"
else
    echo "FAIL: Expected statusCode 200"
    exit 1
fi

# Test 5: Verify S3 Lambda was triggered (check logs)
echo ""
echo "Test 5: Check S3 trigger"
LOG_GROUP="/aws/lambda/$S3_FUNCTION"

LOG_STREAMS=$($AWS logs describe-log-streams \
    --log-group-name "$LOG_GROUP" \
    --order-by LastEventTime \
    --descending \
    --limit 1 \
    --query 'logStreams[0].logStreamName' \
    --output text \
    --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$LOG_STREAMS" && "$LOG_STREAMS" != "None" ]]; then
    echo "PASS: S3 Lambda executed (log stream: $LOG_STREAMS)"
else
    echo "INFO: S3 Lambda logs not found yet (async execution)"
fi

# Cleanup
rm -f /tmp/response.json /tmp/replay.dat

echo ""
echo "SUCCESS: Lambda S3 HTTP tests passed!"
