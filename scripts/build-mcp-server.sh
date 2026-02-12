#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTFILE="bridge/mcp-server.cjs"

printf 'Building %s...\n' "${OUTFILE}" >&2

mkdir -p "${PROJECT_DIR}/bridge"

ESBUILD="${PROJECT_DIR}/node_modules/.bin/esbuild"
if [[ ! -x "${ESBUILD}" ]]; then
  ESBUILD="npx esbuild"
fi

BANNER_FILE="${PROJECT_DIR}/bridge/.banner-tmp-$$.js"
cat > "${BANNER_FILE}" << 'EOF'
// Resolve global npm modules for native package imports
try {
  var _cp = require('child_process');
  var _Module = require('module');
  var _globalRoot = _cp.execSync('npm root -g', { encoding: 'utf8', timeout: 5000 }).trim();
  if (_globalRoot) {
    process.env.NODE_PATH = _globalRoot + (process.env.NODE_PATH ? ':' + process.env.NODE_PATH : '');
    _Module._initPaths();
  }
} catch (_e) { /* npm not available - native modules will gracefully degrade */ }
EOF

cd "${PROJECT_DIR}" || exit 1
${ESBUILD} "src/mcp/standalone-server.ts" \
  --bundle \
  --platform=node \
  --target=node18 \
  --format=cjs \
  --outfile="${OUTFILE}" \
  "--banner:js=$(<"${BANNER_FILE}")" \
  --main-fields=module,main \
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
  --external:module \
  --external:net \
  --external:tls \
  --external:dns \
  --external:readline \
  --external:tty \
  --external:worker_threads \
  "--external:@ast-grep/napi" \
  --external:better-sqlite3

rm -f "${BANNER_FILE}"
printf 'Built %s\n' "${OUTFILE}" >&2
