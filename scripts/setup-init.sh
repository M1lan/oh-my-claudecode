#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input=$(timeout 5 cat 2>/dev/null || true)

result=$(printf '%s' "$input" | node --input-type=module 2>/dev/null <<EOF || printf '%s' '{"continue":true,"suppressOutput":true}'
const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const data = JSON.parse(Buffer.concat(chunks).toString() || '{}');
const { processSetupInit } = await import('file://${SCRIPT_DIR}/../dist/hooks/setup/index.js');
const result = await processSetupInit(data);
process.stdout.write(JSON.stringify(result ?? {"continue":true,"suppressOutput":true}));
EOF
)

printf '%s\n' "${result:-{\"continue\":true,\"suppressOutput\":true}}"
