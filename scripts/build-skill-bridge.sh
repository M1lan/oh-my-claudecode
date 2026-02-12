#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTFILE="dist/hooks/skill-bridge.cjs"
OUTDIR="$(dirname "${PROJECT_DIR}/${OUTFILE}")"

echo "Building ${OUTFILE}..."

mkdir -p "${OUTDIR}"

ESBUILD="${PROJECT_DIR}/node_modules/.bin/esbuild"
if [[ ! -x "${ESBUILD}" ]]; then
  ESBUILD="npx esbuild"
fi

cd "${PROJECT_DIR}"
${ESBUILD} "src/hooks/learner/bridge.ts" \
  --bundle \
  --platform=node \
  --target=node18 \
  --format=cjs \
  --outfile="${OUTFILE}" \
  --external:fs \
  --external:path \
  --external:os \
  --external:util \
  --external:stream \
  --external:events \
  --external:buffer \
  --external:crypto \
  --external:http \
  --external:https \
  --external:url \
  --external:child_process \
  --external:assert \
  --external:module

echo "Built ${OUTFILE}"
