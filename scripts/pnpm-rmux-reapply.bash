#!/usr/bin/env bash
# pnpm-rmux-reapply.bash -- re-apply the pnpm/rmux sweep after an upstream merge
# Usage: pnpm-rmux-reapply.bash [--dry-run] [PATH ...]
set -uo pipefail
trap 'exit 130' INT TERM HUP

(( BASH_VERSINFO[0] >= 5 )) || { printf 'error: bash 5.3+ required\n' >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

DRY_RUN=0
declare -a targets=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) targets+=("$arg") ;;
  esac
done
(( ${#targets[@]} == 0 )) && targets=(.)

EXEMPT_GLOBS=(
  '!pnpm-lock.yaml'
  '!*.lock'
  '!node_modules/**'
  '!dist/**'
  '!.git/**'
  '!scripts/pnpm-rmux-guard.bash'
  '!scripts/pnpm-rmux-reapply.bash'
  '!scripts/pnpm-rmux-guard.allowlist'
)

sd_replace() {
  local pattern=$1 replacement=$2
  local -a rg_args=(--line-number --files-with-matches -P "$pattern")
  local g
  for g in "${EXEMPT_GLOBS[@]}"; do
    rg_args+=(--glob "$g")
  done

  local -a files=()
  mapfile -t files < <(rg "${rg_args[@]}" -- "${targets[@]}" 2>/dev/null || true)
  (( ${#files[@]} == 0 )) && return 0

  local f
  for f in "${files[@]}"; do
    if (( DRY_RUN )); then
      printf 'would replace %q -> %q in %s\n' "$pattern" "$replacement" "$f"
    else
      sd "$pattern" "$replacement" "$f"
      printf 'reapplied %s\n' "$f"
    fi
  done
}

main() {
  # npm -> pnpm (concern 1). Order matters: run -> run before bare install.
  sd_replace '\bnpm run\b' 'pnpm run'
  sd_replace '\bnpx\b' 'pnpm dlx'
  sd_replace '\bnpm install\b' 'pnpm add'
  sd_replace '\bnpm ci\b' 'pnpm install --frozen-lockfile'

  # tmux -> rmux (concern 2). Case-sensitive \btmux\b never matches TMUX / TMUX_TMPDIR
  # env-var reads (those are uppercase) -- so no lookaround needed, and none is
  # supported by sd's Rust regex engine anyway.
  sd_replace '\btmux\b' 'rmux'

  printf 'pnpm-rmux-reapply: done. Run scripts/pnpm-rmux-guard.bash to verify.\n'
}

main
