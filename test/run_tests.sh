#!/bin/bash
# Test runner for Tandem bats test suite.
# Usage: ./test/run_tests.sh [unit|integration|all] [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BATS="$SCRIPT_DIR/lib/bats-core/bin/bats"

if [ ! -x "$BATS" ]; then
  echo "Error: bats-core not found. Run: git submodule update --init --recursive"
  exit 1
fi

SUITE="${1:-all}"
FILTER="${2:-}"

BATS_ARGS=(--timing)
if [ -n "$FILTER" ]; then
  BATS_ARGS+=(--filter "$FILTER")
fi

case "$SUITE" in
  unit)
    "$BATS" "${BATS_ARGS[@]}" "$SCRIPT_DIR/unit/"
    ;;
  integration)
    "$BATS" "${BATS_ARGS[@]}" "$SCRIPT_DIR/integration/"
    ;;
  all)
    "$BATS" "${BATS_ARGS[@]}" "$SCRIPT_DIR/unit/" "$SCRIPT_DIR/integration/"
    ;;
  *)
    echo "Usage: $0 [unit|integration|all] [filter]"
    exit 1
    ;;
esac
