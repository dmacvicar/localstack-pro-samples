#!/bin/bash
set -euo pipefail

# =============================================================================
# Build Matrix Script
# =============================================================================
# Generates a dynamic GitHub Actions matrix based on changed files or all tests.
#
# Usage:
#   ./build-matrix.sh           # Default: uses RUN_MODE env var
#   RUN_MODE=all ./build-matrix.sh
#   RUN_MODE=changed ./build-matrix.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RUN_MODE=${RUN_MODE:-all}

# Infrastructure files that trigger all tests when changed
INFRA_FILES=(
    ".github/workflows/run-samples.yml"
    ".github/scripts/build-matrix.sh"
    "run-samples.sh"
    "Makefile"
    "requirements-dev.txt"
)

# Get all test metadata from run-samples.sh
get_all_tests() {
    cd "$REPO_ROOT"
    ./run-samples.sh --list
}

# Get changed files from git
get_changed_files() {
    if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
        # PR context - compare with base branch
        git fetch origin "$GITHUB_BASE_REF" --depth=1 2>/dev/null || true
        git diff --name-only "origin/$GITHUB_BASE_REF"...HEAD
    elif [[ -n "${GITHUB_SHA:-}" ]]; then
        # Push context - get changed files in the push
        git diff --name-only HEAD~1 HEAD 2>/dev/null || git ls-files
    else
        # Local context - show all files as changed
        git ls-files
    fi
}

# Check if any infrastructure files changed
infra_changed() {
    local changed_files="$1"
    for infra_file in "${INFRA_FILES[@]}"; do
        if echo "$changed_files" | grep -q "^$infra_file$"; then
            return 0
        fi
    done
    return 1
}

# Filter tests based on changed files
filter_tests() {
    local all_tests="$1"
    local changed_files="$2"

    # If infrastructure changed, return all tests
    if infra_changed "$changed_files"; then
        echo "$all_tests"
        return
    fi

    # Filter tests based on watch_folders
    echo "$all_tests" | jq -c --arg changed "$changed_files" '
        map(select(
            .watch_folders as $folders |
            ($folders | split(",")) as $folder_list |
            ($changed | split("\n")) as $changed_list |
            any($folder_list[]; . as $folder |
                any($changed_list[]; startswith($folder))
            )
        ))
    '
}

# Main logic
main() {
    local all_tests
    all_tests=$(get_all_tests)

    if [[ "$RUN_MODE" == "all" ]]; then
        echo "$all_tests"
    else
        local changed_files
        changed_files=$(get_changed_files)

        if [[ -z "$changed_files" ]]; then
            echo "[]"
        else
            filter_tests "$all_tests" "$changed_files"
        fi
    fi
}

main
