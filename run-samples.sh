#!/bin/bash
# LocalStack Pro Samples CI Orchestrator
# Runs AWS samples against LocalStack Pro with sharding support

set -euo pipefail

# Add local bin to PATH for awslocal wrapper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$SCRIPT_DIR/bin:$PATH"

# Sample definitions: "path|ci_command"
# Runs install + run (LocalStack managed externally by CI workflow)
# Only includes samples using services available in LocalStack license
# Only samples that are verified working with current license
SAMPLES=(
  "lambda-function-urls-python|make install && make run"
  "stepfunctions-lambda|make install && make create-lambdas"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Print usage
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --list              List all samples as JSON (for matrix generation)
  --shard N           Run shard N (1-indexed)
  --splits N          Total number of shards
  --sample NAME       Run a specific sample by name
  --help              Show this help message

Examples:
  $0 --list                     # List all samples for CI matrix
  $0 --shard 1 --splits 5       # Run first shard of 5
  $0 --sample lambda-function-urls-python  # Run specific sample
EOF
  exit 0
}

# List all samples as JSON for matrix generation
list_samples() {
  local json='{"include":['
  local first=true
  local idx=1
  local total=${#SAMPLES[@]}

  for sample_def in "${SAMPLES[@]}"; do
    IFS='|' read -r path ci_cmd <<< "$sample_def"
    local name=$(basename "$path")

    if [ "$first" = true ]; then
      first=false
    else
      json+=','
    fi

    json+="{\"shard\":$idx,\"splits\":$total,\"name\":\"$name\",\"path\":\"$path\"}"
    ((idx++))
  done

  json+=']}'
  echo "$json"
}

# Get samples for a specific shard
get_shard_samples() {
  local shard=$1
  local splits=$2
  local total=${#SAMPLES[@]}
  local samples_per_shard=$(( (total + splits - 1) / splits ))
  local start_idx=$(( (shard - 1) * samples_per_shard ))
  local end_idx=$(( start_idx + samples_per_shard ))

  if [ $end_idx -gt $total ]; then
    end_idx=$total
  fi

  for ((i=start_idx; i<end_idx; i++)); do
    echo "${SAMPLES[$i]}"
  done
}

# Cleanup resources between tests
cleanup() {
  log_info "Cleaning up resources..."

  # Clean up CloudFormation stacks
  for stack in $(awslocal cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[].StackName' --output text 2>/dev/null || true); do
    log_info "Deleting stack: $stack"
    awslocal cloudformation delete-stack --stack-name "$stack" 2>/dev/null || true
  done

  # Clean Terraform state
  rm -rf .terraform terraform.tfstate* .terraform.lock.hcl 2>/dev/null || true

  # Clean CDK state
  rm -rf cdk.out 2>/dev/null || true

  # Clean SAM state
  rm -rf .aws-sam 2>/dev/null || true

  log_info "Cleanup complete"
}

# Run a single sample
run_sample() {
  local sample_def=$1
  IFS='|' read -r path ci_cmd <<< "$sample_def"
  local name=$(basename "$path")

  log_info "=========================================="
  log_info "Running sample: $name"
  log_info "Path: $path"
  log_info "=========================================="

  # Change to sample directory
  if [ ! -d "$path" ]; then
    log_error "Sample directory not found: $path"
    return 1
  fi

  pushd "$path" > /dev/null

  # Run CI command
  log_info "Running: $ci_cmd"
  if ! eval "$ci_cmd"; then
    log_error "Test failed for $name"
    popd > /dev/null
    return 1
  fi

  log_info "Sample $name completed successfully"
  popd > /dev/null

  return 0
}

# Find sample by name
find_sample() {
  local name=$1
  for sample_def in "${SAMPLES[@]}"; do
    IFS='|' read -r path ci_cmd <<< "$sample_def"
    local sample_name=$(basename "$path")
    if [ "$sample_name" = "$name" ]; then
      echo "$sample_def"
      return 0
    fi
  done
  return 1
}

# Main
main() {
  local mode=""
  local shard=""
  local splits=""
  local sample_name=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --list)
        mode="list"
        shift
        ;;
      --shard)
        shard="$2"
        shift 2
        ;;
      --splits)
        splits="$2"
        shift 2
        ;;
      --sample)
        sample_name="$2"
        shift 2
        ;;
      --help)
        usage
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        ;;
    esac
  done

  if [ "$mode" = "list" ]; then
    list_samples
    exit 0
  fi

  if [ -n "$sample_name" ]; then
    sample_def=$(find_sample "$sample_name")
    if [ -z "$sample_def" ]; then
      log_error "Sample not found: $sample_name"
      exit 1
    fi
    run_sample "$sample_def"
    exit $?
  fi

  if [ -n "$shard" ] && [ -n "$splits" ]; then
    log_info "Running shard $shard of $splits"
    failed=0
    while IFS= read -r sample_def; do
      if ! run_sample "$sample_def"; then
        ((failed++))
      fi
    done < <(get_shard_samples "$shard" "$splits")

    if [ $failed -gt 0 ]; then
      log_error "$failed sample(s) failed"
      exit 1
    fi
    exit 0
  fi

  # Run all samples if no specific option given
  log_info "Running all samples"
  failed=0
  for sample_def in "${SAMPLES[@]}"; do
    if ! run_sample "$sample_def"; then
      ((failed++))
    fi
  done

  if [ $failed -gt 0 ]; then
    log_error "$failed sample(s) failed"
    exit 1
  fi

  log_info "All samples completed successfully"
}

main "$@"
