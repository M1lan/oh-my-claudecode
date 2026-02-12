#!/usr/bin/env bash
# Platform compatibility shim for OMC hook scripts
# Detects OS and sets tool variables for GNU vs BSD tools
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/lib/platform.sh"

if [[ "$(uname -s)" == "Darwin" ]]; then
  GREP=ggrep; SED=gsed; AWK=gawk; FIND=gfind; DATE=gdate
else
  GREP=grep; SED=sed; AWK=awk; FIND=find; DATE=date
fi
export GREP SED AWK FIND DATE
