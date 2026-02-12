#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTFILE="bridge/codex-server.cjs"
AGENTS_DIR="${PROJECT_DIR}/agents"
CODEX_DIR="${PROJECT_DIR}/agents.codex"

printf 'Building %s...\n' "${OUTFILE}" >&2

mkdir -p "${PROJECT_DIR}/bridge"

ESBUILD="${PROJECT_DIR}/node_modules/.bin/esbuild"
if [[ ! -x "${ESBUILD}" ]]; then
  ESBUILD="npx esbuild"
fi

# ── Collect agent roles and prompts from agents/*.md ────────────────────────
# Strip YAML frontmatter (--- ... ---) from content, keeping only the body.
strip_frontmatter() {
  local file="$1"
  local content
  content=$(<"${file}")
  # If the file starts with ---, strip up to and including the closing ---
  if [[ "${content}" =~ ^---[[:space:]]*$'\n' ]] || [[ "${content:0:3}" == "---" ]]; then
    # Use awk to remove the frontmatter block
    content=$(gawk '/^---/{if(NR==1){found=1;next}if(found){found=0;next}}!found' "${file}" | \
              gawk 'BEGIN{skip=1} /^---$/{if(skip){skip=0;next}} !skip{print}' 2>/dev/null || true)
    # Fallback: simpler sed-based strip
    if [[ -z "${content}" ]]; then
      content=$(gsed -n '/^---$/,/^---$/{/^---$/!p}' "${file}" | tail -n +2)
    fi
    # More reliable: node one-liner for frontmatter strip
    content=$(node -e "
      const fs = require('fs');
      const c = fs.readFileSync('${file}', 'utf-8');
      const m = c.match(/^---[\\s\\S]*?---\\s*([\\s\\S]*)$/);
      process.stdout.write(m ? m[1].trim() : c.trim());
    ")
  fi
  printf '%s' "${content}"
}

# Build JSON for __AGENT_ROLES__, __AGENT_PROMPTS__, __AGENT_PROMPTS_CODEX__
AGENT_ROLES_JSON="["
AGENT_PROMPTS_JSON="{"
first_role=true

# Collect sorted agent .md files
mapfile -t agent_files < <(gfind "${AGENTS_DIR}" -maxdepth 1 -name "*.md" | sort)

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
printf 'Embedding %s agent roles + prompts into %s\n' "${agent_count}" "${OUTFILE}" >&2

# ── Collect Codex-specific prompts from agents.codex/*.md ───────────────────
CODEX_PROMPTS_JSON="{"
first_codex=true
codex_count=0

if [[ -d "${CODEX_DIR}" ]]; then
  mapfile -t codex_files < <(gfind "${CODEX_DIR}" -maxdepth 1 -name "*.md" ! -name "CONVERSION-GUIDE.md" | sort)
  for filepath in "${codex_files[@]}"; do
    filename="$(basename "${filepath}")"
    role="${filename%.md}"

    if [[ "${first_codex}" == "true" ]]; then
      first_codex=false
    else
      CODEX_PROMPTS_JSON+=","
    fi

    prompt=$(node -e "
      const fs = require('fs');
      const c = fs.readFileSync('${filepath}', 'utf-8');
      const m = c.match(/^---[\\s\\S]*?---\\s*([\\s\\S]*)\$/);
      process.stdout.write(JSON.stringify(m ? m[1].trim() : c.trim()));
    ")
    CODEX_PROMPTS_JSON+="$(node -e "process.stdout.write(JSON.stringify('${role}'))")":${prompt}
    (( codex_count++ )) || true
  done
  printf 'Embedding %s Codex agent prompts\n' "${codex_count}" >&2
fi

CODEX_PROMPTS_JSON+="}"

# Warn about agents missing Codex-specific prompts
if [[ -d "${CODEX_DIR}" ]]; then
  for filepath in "${agent_files[@]}"; do
    role="$(basename "${filepath}" .md)"
    if ! node -e "
      const p = ${CODEX_PROMPTS_JSON};
      process.exit(p['${role}'] ? 0 : 1);
    " 2>/dev/null; then
      printf '%s\n' "WARNING: Agent '${role}' has no Codex-specific prompt in agents.codex/" >&2
    fi
  done
fi

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
cd "${PROJECT_DIR}" || exit 1
${ESBUILD} "src/mcp/codex-standalone-server.ts" \
  --bundle \
  --platform=node \
  --target=node18 \
  --format=cjs \
  --outfile="${OUTFILE}" \
  "--banner:js=$(<"${BANNER_FILE}")" \
  "--define:__AGENT_ROLES__=${AGENT_ROLES_JSON}" \
  "--define:__AGENT_PROMPTS__=${AGENT_PROMPTS_JSON}" \
  "--define:__AGENT_PROMPTS_CODEX__=${CODEX_PROMPTS_JSON}" \
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
