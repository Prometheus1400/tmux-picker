#!/usr/bin/env bash
set -eu

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
default_command="${ROOT}/bin/tmux-picker"

option() {
  local name="$1"
  local fallback="$2"
  local value
  value="$(tmux show-option -gqv "$name")"
  printf '%s' "${value:-$fallback}"
}

command="$(option @tmux-picker-command "$default_command")"
key="$(option @tmux-picker-key "o")"

tmux set-environment -g TMUX_PICKER_ROOT "$ROOT"
tmux set-option -gq @tmux-picker-command "$command"

if [ -n "$key" ]; then
  tmux bind-key "$key" run-shell "$command"
fi
