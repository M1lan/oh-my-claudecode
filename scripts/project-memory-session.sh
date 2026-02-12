#!/usr/bin/env bash
set -uo pipefail

# SCRIPT_DIR is not used in this script but kept for consistency with other scripts
# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input=$(timeout 5 cat 2>/dev/null || true)

# Fixed the redirection issue by combining the here-document with the pipe
result=$(printf '%s' "$input" | {
  node --input-type=module 2>/dev/null <<'EOF' || printf '%s' '{"continue":true,"suppressOutput":true}'
const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
let data = {};
try { data = JSON.parse(Buffer.concat(chunks).toString() || '{}'); } catch {}

let registerProjectMemoryContext = null;
try {
  registerProjectMemoryContext = (await import('file://' + __dirname + '/../dist/hooks/project-memory/index.js')).registerProjectMemoryContext;
} catch {}

if (registerProjectMemoryContext) {
  const directory = data.cwd || data.directory || process.cwd();
  const sessionId = data.session_id || data.sessionId || '';
  await registerProjectMemoryContext(sessionId, directory);
}

process.stdout.write(JSON.stringify({"continue":true,"suppressOutput":true}));
EOF
})

printf '%s\n' "${result:-{\"continue\":true,\"suppressOutput\":true}}"
