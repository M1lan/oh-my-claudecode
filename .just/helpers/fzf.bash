#!/usr/bin/env bash
# fzf.bash -- the flat POWER launcher (fzf only, never gum).
# Every recipe in one dense pane, always-on `just --show` preview, multi-select
# (Tab) to batch-run in list order stopping at first failure. No param prompts —
# `just`'s own usage error is the feedback. For someone who knows what they want.
# `--rows` re-emits the list (used by the ctrl-r reload binding).
set -uo pipefail
trap 'exit 130' INT TERM HUP

# shellcheck source-path=SCRIPTDIR source=lib.bash
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1

# ── Row feed: "name  [group]  doc" with group-column tint (fzf --ansi) ────────
rows() {
  just --dump --dump-format json 2> /dev/null | jq -r '
    .recipes | to_entries[]
    | select(.key | startswith("_") | not)
    | select(.key != "default")
    | select([.value.attributes[]? | strings] | index("private") | not)
    | [ .key,
        (([.value.attributes[]? | objects | .group] | first) // "misc"),
        (.value.doc // "")
      ] | @tsv' |
    sort |
    while IFS=$'\t' read -r name grp doc; do
      printf '%-22s \033[36m[%s]\033[0m %s\n' "$name" "$grp" "$doc"
    done
}

if [[ "${1:-}" == "--rows" ]]; then
  rows
  exit 0
fi

has fzf || die 'fzf required (brew install fzf) -- try: just menu'
has jq || die 'jq required (brew install jq)'

self="${BASH_SOURCE[0]}"
header=$'oh-my-claudecode · enter=run · tab=multi-select · ctrl-r=reload · ctrl-/=preview'

mapfile -t picks < <(
  rows | fzf --ansi --multi --style=full \
    --header="$header" \
    --prompt=' ❯ ' \
    --preview 'just --show {1} 2>/dev/null || echo "(no body)"' \
    --preview-window 'right,55%,<80(down)' \
    --bind "ctrl-r:reload($self --rows)" \
    --bind 'ctrl-/:toggle-preview' \
    --bind 'tab:toggle+down,shift-tab:toggle+up' \
    --color 'border:6,label:6,header:3,prompt:6,pointer:6,marker:2,spinner:6,info:8,separator:8,scrollbar:8' \
    --color 'hl:6,hl+:6' || true
)

((${#picks[@]} > 0)) || exit 0

# Batch-run selected recipes in list order, stop at first failure.
recipes=()
for line in "${picks[@]}"; do
  r="${line%% *}"
  [[ -n "$r" ]] && recipes+=("$r")
done
((${#recipes[@]} > 0)) || exit 0

if ((${#recipes[@]} == 1)); then
  exec just "${recipes[0]}"
fi

for r in "${recipes[@]}"; do
  printf '%s── just %s ──%s\n' "$C_BOLD$C_CYAN" "$r" "$C_RESET"
  if ! just "$r"; then
    # shellcheck disable=SC2016  # backtick text is literal display, %s is printf's
    printf '%sstopped: `just %s` failed%s\n' "$C_RED" "$r" "$C_RESET" >&2
    exit 1
  fi
done
