#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input=$(timeout 5 cat 2>/dev/null || true)

printf '%s' "$input" | node --input-type=module 2>/dev/null <<EOF || true
const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const data = JSON.parse(Buffer.concat(chunks).toString() || '{}');

let learnFromToolOutput = null;
let findProjectRoot = null;

try {
  learnFromToolOutput = (await import('file://${SCRIPT_DIR}/../dist/hooks/project-memory/learner.js')).learnFromToolOutput;
} catch {}
try {
  findProjectRoot = (await import('file://${SCRIPT_DIR}/../dist/hooks/rules-injector/finder.js')).findProjectRoot;
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

printf '%s\n' '{"continue":true,"suppressOutput":true}'
