#!/usr/bin/env bash
# pick.bash -- fzf pickers that open the selection in $EDITOR.
# Modes: file (default, source tree) · doc (markdown only) · branch (git switch).
set -uo pipefail
trap 'exit 130' INT TERM HUP

# shellcheck source-path=SCRIPTDIR source=lib.bash
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1

has fzf || die 'fzf required (brew install fzf)'
has fd || die 'fd required (brew install fd)'

mode="${1:-file}"

pick_file() {
  local file
  file="$(fd -e ts -e mjs -e cjs -e js -e json -e md -e toml -e yml -e yaml \
    --exclude node_modules --exclude dist --exclude .git |
    fzf --preview 'bat --color=always --style=numbers --line-range=:500 {} 2>/dev/null || cat {}' \
      --header 'pick a file - enter opens in editor' || true)"
  [[ -z "$file" ]] && exit 0
  exec "${EDITOR:-vim}" "$file"
}

pick_doc() {
  local file
  file="$(fd -e md --exclude node_modules --exclude dist |
    fzf --preview 'bat --color=always --style=numbers --line-range=:500 {} 2>/dev/null || cat {}' \
      --header 'pick a markdown doc' || true)"
  [[ -z "$file" ]] && exit 0
  exec "${EDITOR:-vim}" "$file"
}

pick_branch() {
  has git || die 'git required'
  local branch
  # for-each-ref yields clean short names (no "* "/"  " prefix to strip).
  branch="$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes |
    fzf --preview 'git log --oneline --color=always {} 2>/dev/null | head -50' \
      --header 'switch git branch' || true)"
  [[ -z "$branch" ]] && exit 0
  git switch "${branch#origin/}"
}

case "$mode" in
  file) pick_file ;;
  doc) pick_doc ;;
  branch) pick_branch ;;
  *) die "unknown pick mode: $mode (file|doc|branch)" ;;
esac
