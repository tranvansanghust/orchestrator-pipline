# shellcheck shell=sh
# tmux cockpit (ADR-0011). One session per project, named orchestra-<project>:
#
#   window "cockpit":  Claude TUI (phase 1, and where escalations land)
#                      | watcher: `orchestra status --watch`
#   window "resolve-<id>": opened by `orchestra resolve <id>` for a handoff
#
# Everything degrades without tmux: `design` and `resolve` then open Claude in
# the current terminal.

# tmux_session_name — orchestra-<project>, tmux-safe.
tmux_session_name() {
  printf 'orchestra-%s\n' "$(config_get '.project' | tr -c 'a-zA-Z0-9_-\n' '-')"
}

_tmux_ok() { command -v tmux >/dev/null 2>&1; }

# tmux_open_cockpit — `orchestra design`.
tmux_open_cockpit() {
  _root=$(project_root)
  _planner=$(brain_cmd planner)
  if ! _tmux_ok; then
    log_info "tmux not found; opening Claude here (run 'orchestra status --watch' elsewhere for the dashboard)"
    eval "set -- $_planner"
    cd "$_root" || die "cannot enter $_root"
    exec "$@"
  fi
  _s=$(tmux_session_name)
  if ! tmux has-session -t "$_s" 2>/dev/null; then
    tmux new-session -d -s "$_s" -n cockpit -c "$_root" "$_planner"
    tmux split-window -h -l 40% -t "$_s:cockpit" -c "$_root" \
      "\"$ORCHESTRA_HOME/bin/orchestra\" status --watch"
    tmux select-pane -t "$_s:cockpit.0" -T cockpit
    tmux select-pane -t "$_s:cockpit.1" -T watcher
    tmux select-pane -t "$_s:cockpit.0"
  fi
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$_s"
  else
    exec tmux attach-session -t "$_s"
  fi
}

# tmux_notify <message> — show a message in the cockpit session, if it runs.
tmux_notify() {
  _tmux_ok || return 0
  _s=$(tmux_session_name)
  tmux has-session -t "$_s" 2>/dev/null || return 0
  tmux display-message -t "$_s" -d 10000 "$1" 2>/dev/null || true
}

# tmux_handoff <window> <command> <prompt-file> — open Claude with the prompt in
# a new window of the cockpit session and move the human there. Returns 1 when
# there is no cockpit session (the caller then opens Claude in place).
tmux_handoff() {
  _tmux_ok || return 1
  _s=$(tmux_session_name)
  tmux has-session -t "$_s" 2>/dev/null || return 1
  tmux new-window -t "$_s" -n "$1" -c "$(project_root)" "$2 \"\$(cat '$3')\""
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$_s:$1"
  else
    printf 'Opened window %s in tmux session %s: tmux attach -t %s\n' "$1" "$_s" "$_s"
  fi
}
