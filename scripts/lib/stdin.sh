#!/usr/bin/env bash
# Shared stdin utilities for OMC hook scripts
# Source this file to get the read_stdin function
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/lib/stdin.sh"

# Read all stdin with timeout to prevent indefinite hang (mirrors lib/stdin.mjs)
# Sets global variable STDIN_DATA
# Usage: read_stdin [timeout_seconds]
read_stdin() {
  local timeout_secs="${1:-5}"
  STDIN_DATA=$(timeout "${timeout_secs}" cat 2>/dev/null || true)
}
