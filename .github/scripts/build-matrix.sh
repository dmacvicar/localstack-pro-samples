#!/bin/bash
# Build dynamic matrix for GitHub Actions
# Supports change detection and full runs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Infrastructure files that trigger a full run when changed
INFRA_FILES=(
  "run-samples.sh"
  "Makefile"
  ".github/workflows/run-samples.yml"
  ".github/scripts/build-matrix.sh"
)

# Sample watch folders - maps sample name to folders to watch
# Only includes verified working samples
declare -A WATCH_FOLDERS
WATCH_FOLDERS["lambda-function-urls-python"]="lambda-function-urls-python"
WATCH_FOLDERS["stepfunctions-lambda"]="stepfunctions-lambda"

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --mode MODE         Run mode: 'all' or 'changed' (default: changed)
  --base-sha SHA      Base commit SHA for change detection
  --head-sha SHA      Head commit SHA for change detection
  --help              Show this help message

Environment Variables:
  GITHUB_BASE_REF     Base branch for PR (used if --base-sha not provided)
  GITHUB_SHA          Current commit SHA (used if --head-sha not provided)
EOF
  exit 0
}

# Check if any infrastructure files changed
infra_changed() {
  local base_sha=$1
  local head_sha=$2

  local changed_files=$(git diff --name-only "$base_sha".."$head_sha" 2>/dev/null || echo "")

  for infra_file in "${INFRA_FILES[@]}"; do
    if echo "$changed_files" | grep -q "^$infra_file$"; then
      return 0
    fi
  done

  return 1
}

# Get list of changed samples
get_changed_samples() {
  local base_sha=$1
  local head_sha=$2

  local changed_files=$(git diff --name-only "$base_sha".."$head_sha" 2>/dev/null || echo "")
  local changed_samples=()

  for sample in "${!WATCH_FOLDERS[@]}"; do
    local watch_folder="${WATCH_FOLDERS[$sample]}"
    if echo "$changed_files" | grep -q "^$watch_folder/"; then
      changed_samples+=("$sample")
    fi
  done

  echo "${changed_samples[@]}"
}

# Generate full matrix (all samples)
generate_full_matrix() {
  cd "$ROOT_DIR"
  ./run-samples.sh --list
}

# Generate filtered matrix (only changed samples)
generate_filtered_matrix() {
  local samples=("$@")

  if [ ${#samples[@]} -eq 0 ]; then
    echo '{"include":[]}'
    return
  fi

  local json='{"include":['
  local first=true
  local idx=1
  local total=${#samples[@]}

  for sample in "${samples[@]}"; do
    if [ "$first" = true ]; then
      first=false
    else
      json+=','
    fi
    json+="{\"shard\":$idx,\"splits\":$total,\"name\":\"$sample\",\"path\":\"$sample\"}"
    ((idx++))
  done

  json+=']}'
  echo "$json"
}

main() {
  local mode="changed"
  local base_sha=""
  local head_sha=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --mode)
        mode="$2"
        shift 2
        ;;
      --base-sha)
        base_sha="$2"
        shift 2
        ;;
      --head-sha)
        head_sha="$2"
        shift 2
        ;;
      --help)
        usage
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        ;;
    esac
  done

  # Use environment variables if SHAs not provided
  if [ -z "$base_sha" ] && [ -n "${GITHUB_BASE_REF:-}" ]; then
    base_sha="origin/$GITHUB_BASE_REF"
  fi

  if [ -z "$head_sha" ]; then
    head_sha="${GITHUB_SHA:-HEAD}"
  fi

  cd "$ROOT_DIR"

  # Mode: all - run everything
  if [ "$mode" = "all" ]; then
    generate_full_matrix
    exit 0
  fi

  # Mode: changed - check what needs to run
  if [ -z "$base_sha" ]; then
    echo "No base SHA provided, running all samples" >&2
    generate_full_matrix
    exit 0
  fi

  # Check if infrastructure changed
  if infra_changed "$base_sha" "$head_sha"; then
    echo "Infrastructure files changed, running all samples" >&2
    generate_full_matrix
    exit 0
  fi

  # Get changed samples
  changed_samples=($(get_changed_samples "$base_sha" "$head_sha"))

  if [ ${#changed_samples[@]} -eq 0 ]; then
    echo "No samples changed" >&2
    echo '{"include":[]}'
    exit 0
  fi

  echo "Changed samples: ${changed_samples[*]}" >&2
  generate_filtered_matrix "${changed_samples[@]}"
}

main "$@"
