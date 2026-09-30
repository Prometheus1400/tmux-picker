#!/usr/bin/env bash
set -eu

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

option() {
  local name="$1"
  local fallback="$2"
  if [ -n "$(tmux show-option -gq "$name")" ]; then
    tmux show-option -gqv "$name"
  else
    printf '%s' "$fallback"
  fi
}

shell_quote() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}

default_command="$(shell_quote "${ROOT}/bin/tmux-picker")"
previous_default="$(option @tmux-picker-default-command '')"
command="$(option @tmux-picker-command "$default_command")"
if [ "$command" = "$previous_default" ]; then
  command="$default_command"
fi
key="$(option @tmux-picker-key 'o')"
previous_key="$(option @tmux-picker-bound-key '')"
previous_binding="$(option @tmux-picker-binding '')"

# Remove only a binding that still matches the one installed by this plugin.
if [ -n "$previous_key" ] && [ "$previous_key" != "$key" ]; then
  binding="$(tmux list-keys -T prefix "$previous_key" 2>/dev/null || true)"
  if [ -n "$previous_binding" ] && [ "$binding" = "$previous_binding" ]; then
    tmux unbind-key "$previous_key"
  fi
fi

tmux set-environment -g TMUX_PICKER_ROOT "$ROOT"
tmux set-option -gq @tmux-picker-default-command "$default_command"
tmux set-option -gq @tmux-picker-command "$command"
tmux set-option -gq @tmux-picker-bound-key "$key"

if [ -n "$key" ]; then
  tmux bind-key "$key" run-shell "$command"
  tmux set-option -gq @tmux-picker-binding "$(tmux list-keys -T prefix "$key")"
else
  tmux set-option -gqu @tmux-picker-binding
fi
