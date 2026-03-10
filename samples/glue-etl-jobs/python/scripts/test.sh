#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "FAIL: .env file not found. Run deploy.sh first."
    exit 1
fi

source "$SCRIPT_DIR/.env"

PASS=0
FAIL=0

check() {
    local description=$1
    shift
    if "$@" > /dev/null 2>&1; then
        echo "PASS: $description"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $description"
        FAIL=$((FAIL + 1))
    fi
}

echo "Testing Glue ETL Jobs..."
echo "========================"

# Test Glue database exists
check "Glue database exists" \
    awslocal glue get-database --name legislators

# Test Glue tables exist
for table in persons_json memberships_json organizations_json; do
    check "Glue table $table exists" \
        awslocal glue get-table --database-name legislators --name "$table"
done

# Test Glue connection exists
check "Glue connection exists" \
    awslocal glue get-connection --name "$CONNECTION_NAME"

# Test Glue job exists
check "Glue job exists" \
    awslocal glue get-job --job-name "$JOB_NAME"

# Test job run succeeded
STATE=$(awslocal glue get-job-run --job-name "$JOB_NAME" --run-id "$JOB_RUN_ID" | jq -r '.JobRun.JobRunState')
if [ "$STATE" = "SUCCEEDED" ]; then
    echo "PASS: Glue job run succeeded"
    PASS=$((PASS + 1))
else
    echo "FAIL: Glue job run state is $STATE (expected SUCCEEDED)"
    FAIL=$((FAIL + 1))
fi

# Test S3 output exists
OUTPUT_COUNT=$(awslocal s3 ls "s3://${TARGET_BUCKET}/output-dir/" --recursive 2>/dev/null | wc -l)
if [ "$OUTPUT_COUNT" -gt 0 ]; then
    echo "PASS: S3 output files exist ($OUTPUT_COUNT files)"
    PASS=$((PASS + 1))
else
    echo "FAIL: No output files found in S3"
    FAIL=$((FAIL + 1))
fi

# Test S3 script bucket has job.py
check "Job script exists in S3" \
    awslocal s3 ls "s3://${BUCKET}/job.py"

echo ""
echo "========================"
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
