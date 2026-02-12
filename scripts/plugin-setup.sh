#!/usr/bin/env bash
# Plugin Post-Install Setup
# Configures HUD statusline when plugin is installed.
# Bash port of plugin-setup.mjs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
HUD_DIR="${CLAUDE_DIR}/hud"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
HUD_SCRIPT="${HUD_DIR}/omc-hud.mjs"

echo "[OMC] Running post-install setup..."

# 1. Create HUD directory
mkdir -p "$HUD_DIR"

# 2. Write omc-hud.mjs wrapper script
cat > "$HUD_SCRIPT" <<'HUDEOF'
#!/usr/bin/env node
/**
 * OMC HUD - Statusline Script
 * Wrapper that imports from plugin cache or development paths
 */

import { existsSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// Semantic version comparison: returns negative if a < b, positive if a > b, 0 if equal
function semverCompare(a, b) {
  // Use parseInt to handle pre-release suffixes (e.g. "0-beta" -> 0)
  const pa = a.replace(/^v/, "").split(".").map(s => parseInt(s, 10) || 0);
  const pb = b.replace(/^v/, "").split(".").map(s => parseInt(s, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const na = pa[i] || 0;
    const nb = pb[i] || 0;
    if (na !== nb) return na - nb;
  }
  // If numeric parts equal, non-pre-release > pre-release
  const aHasPre = /-/.test(a);
  const bHasPre = /-/.test(b);
  if (aHasPre && !bHasPre) return -1;
  if (!aHasPre && bHasPre) return 1;
  return 0;
}

async function main() {
  const home = homedir();

  // 1. Try plugin cache first (marketplace: omc, plugin: oh-my-claudecode)
  const pluginCacheBase = join(home, ".claude/plugins/cache/omc/oh-my-claudecode");
  if (existsSync(pluginCacheBase)) {
    try {
      const versions = readdirSync(pluginCacheBase);
      if (versions.length > 0) {
        // Filter to only versions with built dist/hud/index.js
        const builtVersions = versions.filter(v => {
          const hudPath = join(pluginCacheBase, v, "dist/hud/index.js");
          return existsSync(hudPath);
        });
        if (builtVersions.length > 0) {
          const latestBuilt = builtVersions.sort(semverCompare).reverse()[0];
          const pluginPath = join(pluginCacheBase, latestBuilt, "dist/hud/index.js");
          await import(pluginPath);
          return;
        }
      }
    } catch { /* continue */ }
  }

  // 2. Development paths
  const devPaths = [
    join(home, "Workspace/oh-my-claude-sisyphus/dist/hud/index.js"),
    join(home, "workspace/oh-my-claude-sisyphus/dist/hud/index.js"),
    join(home, "Workspace/oh-my-claudecode/dist/hud/index.js"),
    join(home, "workspace/oh-my-claudecode/dist/hud/index.js"),
  ];

  for (const devPath of devPaths) {
    if (existsSync(devPath)) {
      try {
        await import(devPath);
        return;
      } catch { /* continue */ }
    }
  }

  // 3. Fallback
  console.log("[OMC] run /omc-setup to install properly");
}

main();
HUDEOF

chmod 755 "$HUD_SCRIPT" 2>/dev/null || true
echo "[OMC] Installed HUD wrapper script"

# 3. Configure settings.json
if settings=$(jq '.' "$SETTINGS_FILE" 2>/dev/null); then
  true
else
  settings='{}'
fi

settings=$(printf '%s' "$settings" | jq --arg cmd "node ${HUD_SCRIPT}" \
  '.statusLine = {"type": "command", "command": $cmd}' 2>/dev/null) || {
  echo "[OMC] Warning: Could not configure settings.json: jq error"
  echo "[OMC] Setup complete! Restart Claude Code to activate HUD."
  exit 0
}

printf '%s\n' "$settings" > "$SETTINGS_FILE"
echo "[OMC] Configured HUD statusLine in settings.json"
echo "[OMC] Setup complete! Restart Claude Code to activate HUD."
