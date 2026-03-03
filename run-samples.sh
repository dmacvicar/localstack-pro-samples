#!/bin/bash
set -euo pipefail

# =============================================================================
# LocalStack Pro Samples - Test Runner
# =============================================================================
# This script runs sample tests with support for sharding in CI environments.
#
# Usage:
#   ./run-samples.sh                    # Run all samples
#   ./run-samples.sh SHARD=1 SPLITS=5   # Run first shard of 5
#   ./run-samples.sh --list             # Output JSON metadata for CI matrix
# =============================================================================

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        SHARD=*)
            SHARD="${arg#*=}"
            ;;
        SPLITS=*)
            SPLITS="${arg#*=}"
            ;;
        --list)
            LIST_MODE=true
            ;;
    esac
done

SHARD=${SHARD:-1}
SPLITS=${SPLITS:-1}
LIST_MODE=${LIST_MODE:-false}

# =============================================================================
# Sample Definitions
# Format: "path|deploy_command|test_command|watch_folders"
# =============================================================================

SCRIPT_SAMPLES=(
    "samples/lambda-cloudfront/python|scripts/deploy.sh|scripts/test.sh|samples/lambda-cloudfront/python/scripts,samples/lambda-cloudfront/python/src"
    "samples/lambda-s3-http/python|scripts/deploy.sh|scripts/test.sh|samples/lambda-s3-http/python/scripts,samples/lambda-s3-http/python/src"
    "samples/web-app-dynamodb/python|scripts/deploy.sh|scripts/test.sh|samples/web-app-dynamodb/python/scripts,samples/web-app-dynamodb/python/src"
    "samples/web-app-rds/python|scripts/deploy.sh|scripts/test.sh|samples/web-app-rds/python/scripts,samples/web-app-rds/python/src"
)

TERRAFORM_SAMPLES=(
    # Terraform samples can be added here
    # "samples/lambda-cloudfront/python|terraform/deploy.sh|scripts/test.sh|samples/lambda-cloudfront/python/terraform,samples/lambda-cloudfront/python/src"
)

# Combine all samples
ALL_SAMPLES=("${SCRIPT_SAMPLES[@]}" "${TERRAFORM_SAMPLES[@]}")

# =============================================================================
# List Mode - Output JSON for CI Matrix
# =============================================================================

if [[ "$LIST_MODE" == "true" ]]; then
    # Output compact JSON for GitHub Actions matrix
    output="["
    first=true
    shard=1
    for sample in "${ALL_SAMPLES[@]}"; do
        IFS='|' read -r path deploy test watch_folders <<< "$sample"
        name=$(basename "$(dirname "$path")")/$(basename "$path")

        if [[ "$first" == "true" ]]; then
            first=false
        else
            output+=","
        fi

        output+="{\"shard\":$shard,\"splits\":${#ALL_SAMPLES[@]},\"name\":\"$name\",\"path\":\"$path\",\"watch_folders\":\"$watch_folders\"}"
        ((shard++))
    done
    output+="]"
    echo "$output"
    exit 0
fi

# =============================================================================
# Tool Verification
# =============================================================================

check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: $1 is required but not installed."
        exit 1
    fi
}

echo "Verifying required tools..."
check_tool docker
check_tool aws
check_tool jq

# Check for awslocal
if ! command -v awslocal &> /dev/null; then
    echo "Warning: awslocal not found, using 'aws --endpoint-url=http://localhost:4566'"
    AWS="aws --endpoint-url=http://localhost:4566"
else
    AWS="awslocal"
fi

# =============================================================================
# Environment Setup
# =============================================================================

# Load .env if present
if [[ -f .env ]]; then
    echo "Loading .env file..."
    set -a
    source .env
    set +a
fi

# Configure AWS CLI for LocalStack
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

# =============================================================================
# LocalStack Health Check
# =============================================================================

wait_for_localstack() {
    echo "Waiting for LocalStack to be ready..."
    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -s http://localhost:4566/_localstack/health | jq -e '.services' > /dev/null 2>&1; then
            echo "LocalStack is ready!"
            return 0
        fi
        echo "Attempt $attempt/$max_attempts - waiting..."
        sleep 2
        ((attempt++))
    done

    echo "Error: LocalStack did not become ready in time"
    exit 1
}

# Check if LocalStack is running
if ! curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; then
    echo "LocalStack is not running. Please start it first:"
    echo "  docker run -d --name localstack -p 4566:4566 -e LOCALSTACK_AUTH_TOKEN localstack/localstack-pro"
    exit 1
fi

wait_for_localstack

# =============================================================================
# Calculate Shard Range
# =============================================================================

total_samples=${#ALL_SAMPLES[@]}
samples_per_shard=$(( (total_samples + SPLITS - 1) / SPLITS ))
start_index=$(( (SHARD - 1) * samples_per_shard ))
end_index=$(( start_index + samples_per_shard ))

if [[ $end_index -gt $total_samples ]]; then
    end_index=$total_samples
fi

echo "Running shard $SHARD of $SPLITS (samples $((start_index + 1)) to $end_index of $total_samples)"

# =============================================================================
# Run Tests
# =============================================================================

failed_samples=()
passed_samples=()

for ((i = start_index; i < end_index; i++)); do
    sample="${ALL_SAMPLES[$i]}"
    IFS='|' read -r path deploy test watch_folders <<< "$sample"

    sample_name=$(basename "$(dirname "$path")")/$(basename "$path")
    echo ""
    echo "============================================================================="
    echo "Running: $sample_name"
    echo "============================================================================="

    cd "$path" || continue

    # Deploy
    echo "Deploying..."
    if ! bash "$deploy"; then
        echo "ERROR: Deployment failed for $sample_name"
        failed_samples+=("$sample_name")
        cd - > /dev/null
        continue
    fi

    # Test
    echo "Testing..."
    if ! bash "$test"; then
        echo "ERROR: Tests failed for $sample_name"
        failed_samples+=("$sample_name")
    else
        echo "SUCCESS: $sample_name passed"
        passed_samples+=("$sample_name")
    fi

    cd - > /dev/null

    # Cleanup between tests
    echo "Cleaning up..."
    docker system prune -f > /dev/null 2>&1 || true
done

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "============================================================================="
echo "Test Summary"
echo "============================================================================="
echo "Passed: ${#passed_samples[@]}"
for sample in "${passed_samples[@]}"; do
    echo "  - $sample"
done

if [[ ${#failed_samples[@]} -gt 0 ]]; then
    echo ""
    echo "Failed: ${#failed_samples[@]}"
    for sample in "${failed_samples[@]}"; do
        echo "  - $sample"
    done
    exit 1
fi

echo ""
echo "All tests passed!"
