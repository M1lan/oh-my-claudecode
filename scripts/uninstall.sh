#!/usr/bin/env bash
# Oh-My-Claude-Sisyphus Uninstaller
# Completely removes all Sisyphus-installed files and configurations
# shellcheck disable=SC2059

set -uo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

printf "${BLUE}Oh-My-Claude-Sisyphus Uninstaller${NC}\n"
printf '\n'

# Claude Code config directory (always ~/.claude)
CLAUDE_CONFIG_DIR="$HOME/.claude"

printf 'This will remove ALL Sisyphus components from:\n'
printf '  %s\n' "$CLAUDE_CONFIG_DIR"
printf '\n'
printf 'Components to be removed:\n'
printf '  - Agents (oracle, librarian, explore, etc.)\n'
printf '  - Commands (sisyphus, ultrawork, plan, etc.)\n'
printf '  - Skills (ultrawork, git-master, frontend-ui-ux)\n'
printf '  - Hooks (keyword-detector, silent-auto-update, stop-continuation)\n'
printf '  - Version and state files\n'
printf '  - Hook configurations from settings.json\n'
printf '\n'
if [[ -t 0 ]]; then
    read -p "Continue? (y/N) " -n 1 -r
    printf '\n'
else
    # Try reading from terminal if script is piped
    if [[ -c /dev/tty ]]; then
        printf 'Continue? (y/N) ' >&2
        read -n 1 -r < /dev/tty
        printf '\n'
    else
        printf 'Non-interactive mode detected or terminal not available. Uninstallation cancelled.\n'
        exit 1
    fi
fi

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    printf 'Cancelled.\n'
    exit 0
fi

# Remove agents
printf "${BLUE}Removing agents...${NC}\n"
rm -f "$CLAUDE_CONFIG_DIR/agents/oracle.md"
rm -f "$CLAUDE_CONFIG_DIR/agents/librarian.md"
rm -f "$CLAUDE_CONFIG_DIR/agents/explore.md"
rm -f "$CLAUDE_CONFIG_DIR/agents/frontend-engineer.md"
rm -f "$CLAUDE_CONFIG_DIR/agents/document-writer.md"
rm -f "$CLAUDE_CONFIG_DIR/agents/multimodal-looker.md"
rm -f "$CLAUDE_CONFIG_DIR/agents/momus.md"
rm -f "$CLAUDE_CONFIG_DIR/agents/metis.md"
rm -f "$CLAUDE_CONFIG_DIR/agents/sisyphus-junior.md"
rm -f "$CLAUDE_CONFIG_DIR/agents/prometheus.md"

# Remove commands
printf "${BLUE}Removing commands...${NC}\n"
rm -f "$CLAUDE_CONFIG_DIR/commands/sisyphus.md"
rm -f "$CLAUDE_CONFIG_DIR/commands/ultrawork.md"
rm -f "$CLAUDE_CONFIG_DIR/commands/deepsearch.md"
rm -f "$CLAUDE_CONFIG_DIR/commands/analyze.md"
rm -f "$CLAUDE_CONFIG_DIR/commands/plan.md"
rm -f "$CLAUDE_CONFIG_DIR/commands/review.md"
rm -f "$CLAUDE_CONFIG_DIR/commands/prometheus.md"
rm -f "$CLAUDE_CONFIG_DIR/commands/orchestrator.md"
rm -f "$CLAUDE_CONFIG_DIR/commands/update.md"

# Remove skills
printf "${BLUE}Removing skills...${NC}\n"
rm -rf "$CLAUDE_CONFIG_DIR/skills/ultrawork"
rm -rf "$CLAUDE_CONFIG_DIR/skills/git-master"
rm -rf "$CLAUDE_CONFIG_DIR/skills/frontend-ui-ux"

# Remove hooks
printf "${BLUE}Removing hooks...${NC}\n"
rm -f "$CLAUDE_CONFIG_DIR/hooks/keyword-detector.sh"
rm -f "$CLAUDE_CONFIG_DIR/hooks/stop-continuation.sh"
rm -f "$CLAUDE_CONFIG_DIR/hooks/silent-auto-update.sh"

# Remove version, state, and config files
printf "${BLUE}Removing state and config files...${NC}\n"
rm -f "$CLAUDE_CONFIG_DIR/.omc-version.json"
rm -f "$CLAUDE_CONFIG_DIR/.omc-silent-update.json"
rm -f "$CLAUDE_CONFIG_DIR/.omc-update.log"
rm -f "$CLAUDE_CONFIG_DIR/.omc-config.json"

# Remove hook configurations from settings.json
SETTINGS_FILE="$CLAUDE_CONFIG_DIR/settings.json"
if [[ -f "$SETTINGS_FILE" ]] && command -v jq &> /dev/null; then
    printf "${BLUE}Removing hook configurations from settings.json...${NC}\n"

    # Create a backup
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"

    # Remove Sisyphus-specific hooks from settings.json
    # This removes hooks that reference sisyphus hook scripts
    TEMP_SETTINGS=$(mktemp)

    # Use jq to filter out Sisyphus hooks
    if jq '
      # Remove Sisyphus hooks from UserPromptSubmit
      if .hooks.UserPromptSubmit then
        .hooks.UserPromptSubmit |= map(
          if .hooks then
            .hooks |= map(select(.command | (contains("keyword-detector.sh") or contains("silent-auto-update.sh") or contains("stop-continuation.sh")) | not))
          else .
          end
        ) | .hooks.UserPromptSubmit |= map(select(.hooks | length > 0))
      else . end |

      # Remove Sisyphus hooks from Stop
      if .hooks.Stop then
        .hooks.Stop |= map(
          if .hooks then
            .hooks |= map(select(.command | (contains("keyword-detector.sh") or contains("silent-auto-update.sh") or contains("stop-continuation.sh")) | not))
          else .
          end
        ) | .hooks.Stop |= map(select(.hooks | length > 0))
      else . end |

      # Clean up empty hooks sections
      if .hooks.UserPromptSubmit == [] then del(.hooks.UserPromptSubmit) else . end |
      if .hooks.Stop == [] then del(.hooks.Stop) else . end |
      if .hooks == {} then del(.hooks) else . end
    ' "$SETTINGS_FILE" > "$TEMP_SETTINGS" 2>/dev/null && [[ -s "$TEMP_SETTINGS" ]]; then
        mv "$TEMP_SETTINGS" "$SETTINGS_FILE"
        printf "${GREEN}Removed Sisyphus hooks from settings.json${NC}\n"
        printf "${YELLOW}  Backup saved to: %s.bak${NC}\n" "$SETTINGS_FILE"
    else
        rm -f "$TEMP_SETTINGS"
        printf "${YELLOW}Could not modify settings.json automatically${NC}\n"
        printf '  Please manually remove Sisyphus hooks from the hooks section\n'
    fi
else
    if [[ -f "$SETTINGS_FILE" ]]; then
        printf "${YELLOW}jq not installed - cannot auto-remove hooks from settings.json${NC}\n"
        printf '  Please manually edit %s and remove the following hooks:\n' "$SETTINGS_FILE"
        printf '    - keyword-detector.sh\n'
        printf '    - silent-auto-update.sh\n'
        printf '    - stop-continuation.sh\n'
    fi
fi

# Remove .omc directory if it exists (plans, notepads, drafts)
if [[ -d "$CLAUDE_CONFIG_DIR/../.omc" ]] || [[ -d ".omc" ]]; then
    printf "${YELLOW}Note: .omc directory (plans/notepads) was not removed.${NC}\n"
    printf '  To remove project plans and notepads, run:\n'
    printf '    rm -rf .omc\n'
fi

printf '\n'
printf "${GREEN}Uninstallation complete!${NC}\n"
printf '\n'
printf "${YELLOW}Items NOT removed (manual cleanup if desired):${NC}\n"
printf '  - CLAUDE.md: rm %s/CLAUDE.md\n' "$CLAUDE_CONFIG_DIR"
printf '  - settings.json backup: rm %s/settings.json.bak\n' "$CLAUDE_CONFIG_DIR"
printf '\n'
printf 'To verify complete removal, check:\n'
printf '  ls -la %s/\n' "$CLAUDE_CONFIG_DIR"
