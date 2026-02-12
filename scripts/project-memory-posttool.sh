#!/usr/bin/env bash
set -euo pipefail

# SCRIPT_DIR is not used in this script but kept for consistency with other scripts
# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input=$(timeout 5 cat 2>/dev/null || true)

_tmpjs=$(mktemp /tmp/omc-posttool-XXXXXX.mjs)
trap 'rm -f "$_tmpjs"' EXIT INT TERM
cat > "$_tmpjs" <<'EOF'
const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const data = JSON.parse(Buffer.concat(chunks).toString() || '{}');

let learnFromToolOutput = null;
let findProjectRoot = null;

try {
  learnFromToolOutput = (await import('file://' + __dirname + '/../dist/hooks/project-memory/learner.js')).learnFromToolOutput;
} catch {}
try {
  findProjectRoot = (await import('file://' + __dirname + '/../dist/hooks/rules-injector/finder.js')).findProjectRoot;
} catch {}

if (learnFromToolOutput && findProjectRoot) {
  const directory = data.cwd || data.directory || process.cwd();
  const projectRoot = findProjectRoot(directory);
  if (projectRoot) {
    await learnFromToolOutput(
      data.tool_name || data.toolName || '',
      data.tool_input || data.toolInput || {},
      data.tool_response || data.toolOutput || '',
      projectRoot
    );
  }
}
EOF
printf '%s' "$input" | node --input-type=module "$_tmpjs" 2>/dev/null || true

printf '%s\n' '{"continue":true,"suppressOutput":true}'
