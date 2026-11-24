# shellcheck shell=sh
# Shared runtime for adapters. An adapter sources nothing itself; the engine
# (or a test) sources common.sh, config.sh and this file, then the adapter.
#
# Two execution models (ADR-0006):
#   run-to-exit : the CLI runs once and exits; "done" = process exit. No tmux.
#                 opencode, claude and mock use this via the helpers below.
#   pane-parse  : a TUI-only CLI; adapter_wait parses a tmux pane (roadmap
#                 step 5). Its mess stays inside that one adapter.
#
# Per-task runtime files, under .bus/agents/:
#   <task>.log    combined stdout+stderr of the run
#   <task>.pid    the background pid (run-to-exit)
#   <task>.exit   the exit code, written atomically when the run finishes

# run_to_exit_dispatch <task-id> <workdir> <cmd> [args...]
# Start the command in workdir, in the background, and return immediately.
run_to_exit_dispatch() {
  _task=$1
  _wd=$2
  shift 2
  _adir=$(bus_dir)/agents
  mkdir -p "$_adir"
  _log=$_adir/$_task.log
  _exit=$_adir/$_task.exit
  rm -f "$_exit" "$_adir/$_task.pid"
  (
    if cd "$_wd" 2>/dev/null; then
      # `&& || ` keeps the non-zero exit from tripping `set -e` before we record it.
      "$@" >"$_log" 2>&1 && _rc=0 || _rc=$?
    else
      printf 'adapter: cannot cd into %s\n' "$_wd" >"$_log"
      _rc=127
    fi
    printf '%s\n' "$_rc" >"$_exit.tmp" && mv "$_exit.tmp" "$_exit"
  ) &
  printf '%s\n' "$!" >"$_adir/$_task.pid"
}

# run_to_exit_wait <task-id> [timeout-seconds]
# Block until the run finishes. 0 = exit 0, 1 = non-zero exit, 124 = timeout.
# On timeout, best-effort terminate the run so a runaway agent is not leaked.
run_to_exit_wait() {
  _task=$1
  _timeout=${2:-0}
  _adir=$(bus_dir)/agents
  _exit=$_adir/$_task.exit
  _waited=0
  while [ ! -f "$_exit" ]; do
    if [ "$_timeout" -gt 0 ] && [ "$_waited" -ge "$_timeout" ]; then
      run_to_exit_kill "$_task"
      return 124
    fi
    sleep 1
    _waited=$((_waited + 1))
  done
  _rc=$(cat "$_exit")
  [ "$_rc" = "0" ]
}

# run_to_exit_kill <task-id> — best-effort terminate a running agent and its
# direct children. Thorough process-group cleanup lands with the daemon
# (macOS has no setsid); this stops the common case of a runaway CLI.
run_to_exit_kill() {
  _pidfile=$(bus_dir)/agents/$1.pid
  [ -f "$_pidfile" ] || return 0
  _pid=$(cat "$_pidfile")
  [ -n "$_pid" ] || return 0
  pkill -TERM -P "$_pid" 2>/dev/null || true
  kill -TERM "$_pid" 2>/dev/null || true
}

# agent_log_path <task-id> — where this task's agent output was written.
agent_log_path() {
  printf '%s/agents/%s.log\n' "$(bus_dir)" "$1"
}
