#!/usr/bin/env bash
# search.bash -- live ripgrep -> fzf -> bat preview -> $EDITOR at the match.
# Reloads results on every keystroke. Usage: search.bash [initial-query]
set -uo pipefail
trap 'exit 130' INT TERM HUP

# shellcheck source-path=SCRIPTDIR source=lib.bash
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1

has fzf || die 'fzf required (brew install fzf)'
has rg || die 'rg required (brew install ripgrep)'

query="${1:-}"
rg_cmd='rg --line-number --no-heading --color=always --smart-case \
  --glob !node_modules --glob !dist --glob !.git'

line="$(
  FZF_DEFAULT_COMMAND="$rg_cmd -- $(printf '%q' "$query")" \
    fzf --ansi --disabled --query "$query" \
    --delimiter=':' \
    --bind "change:reload:sleep 0.05; $rg_cmd -- {q} || true" \
    --preview 'bat --color=always --style=numbers --highlight-line {2} {1} 2>/dev/null || cat {1}' \
    --preview-window 'right,60%,+{2}+3/2,~3' \
    --header 'live rg · type to search · enter opens at line' || true
)"

[[ -z "$line" ]] && exit 0
file="${line%%:*}"
rest="${line#*:}"
lno="${rest%%:*}"
exec "${EDITOR:-vim}" "+${lno}" "$file"
