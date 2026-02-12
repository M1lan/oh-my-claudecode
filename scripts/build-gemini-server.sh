#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTFILE="bridge/gemini-server.cjs"
AGENTS_DIR="${PROJECT_DIR}/agents"

echo "Building ${OUTFILE}..."

mkdir -p "${PROJECT_DIR}/bridge"

ESBUILD="${PROJECT_DIR}/node_modules/.bin/esbuild"
if [[ ! -x "${ESBUILD}" ]]; then
  ESBUILD="npx esbuild"
fi

# ── Collect agent roles and prompts from agents/*.md ────────────────────────
AGENT_ROLES_JSON="["
AGENT_PROMPTS_JSON="{"
first_role=true

mapfile -t agent_files < <(find "${AGENTS_DIR}" -maxdepth 1 -name "*.md" | sort)

for filepath in "${agent_files[@]}"; do
  filename="$(basename "${filepath}")"
  role="${filename%.md}"

  if [[ "${first_role}" == "true" ]]; then
    first_role=false
  else
    AGENT_ROLES_JSON+=","
    AGENT_PROMPTS_JSON+=","
  fi

  AGENT_ROLES_JSON+="$(node -e "process.stdout.write(JSON.stringify('${role}'))")"

  prompt=$(node -e "
    const fs = require('fs');
    const c = fs.readFileSync('${filepath}', 'utf-8');
    const m = c.match(/^---[\\s\\S]*?---\\s*([\\s\\S]*)\$/);
    process.stdout.write(JSON.stringify(m ? m[1].trim() : c.trim()));
  ")
  AGENT_PROMPTS_JSON+="$(node -e "process.stdout.write(JSON.stringify('${role}'))")":${prompt}
done

AGENT_ROLES_JSON+="]"
AGENT_PROMPTS_JSON+="}"

agent_count="${#agent_files[@]}"
echo "Embedding ${agent_count} agent roles + prompts into ${OUTFILE}"

# ── Banner ───────────────────────────────────────────────────────────────────
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

# ── esbuild ──────────────────────────────────────────────────────────────────
cd "${PROJECT_DIR}"
${ESBUILD} "src/mcp/gemini-standalone-server.ts" \
  --bundle \
  --platform=node \
  --target=node18 \
  --format=cjs \
  --outfile="${OUTFILE}" \
  "--banner:js=$(cat "${BANNER_FILE}")" \
  "--define:__AGENT_ROLES__=${AGENT_ROLES_JSON}" \
  "--define:__AGENT_PROMPTS__=${AGENT_PROMPTS_JSON}" \
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
echo "Built ${OUTFILE}"
