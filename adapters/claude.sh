# shellcheck shell=sh
# Adapter: Claude Code as a coding agent (`claude -p`, headless). Run-to-exit.
# This is the coding-agent role; the reviewer/confirmer run through
# lib/review.sh with brain.reviewer, not through this adapter.

adapter_spawn() {
  command -v claude >/dev/null 2>&1 || {
    log_warn "claude not found on PATH"
    return 1
  }
  return 0
}

adapter_dispatch() {
  # <agent> <task-id> <spec-file> <workdir>
  _agent=$1
  _task=$2
  _spec=$3
  _wd=$4
  _model=$(agent_field "$_agent" '.model // empty')

  # --dangerously-skip-permissions for an unattended run; safe for the same
  # reason as the opencode adapter (isolated worktree + MERGE gate).
  set -- claude -p --output-format json --dangerously-skip-permissions
  [ -n "$_model" ] && set -- "$@" --model "$_model"
  set -- "$@" "$(cat "$_spec")"
  run_to_exit_dispatch "$_task" "$_wd" "$@"
}

adapter_wait() {
  run_to_exit_wait "$2" "${3:-0}"
}

adapter_capability() {
  printf '%s\n' backend api frontend algo refactor
}
