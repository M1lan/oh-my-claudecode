#!/usr/bin/env bash
set -euo pipefail

# SCRIPT_DIR is not used in this script but kept for consistency with other scripts
# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input=$(timeout 5 cat 2>/dev/null || true)

# Fixed the redirection issue by combining the here-document with the pipe
result=$(printf '%s' "$input" | {
  node --input-type=module - 2>/dev/null <<'JSEOF' || printf '%s' '{"continue":true,"suppressOutput":true}'
const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const data = JSON.parse(Buffer.concat(chunks).toString() || '{}');
const { processPermissionRequest } = await import(new URL('../dist/hooks/permission-handler/index.js', new URL('file://' + process.env.PWD + '/')));
const result = await processPermissionRequest(data);
process.stdout.write(JSON.stringify(result));
JSEOF
})

printf '%s\n' "$result"
