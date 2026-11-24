# shellcheck shell=sh
# Adapter: OpenCode (`opencode run`, headless). Run-to-exit. Drives any model
# OpenCode supports via the agent's `model` field (e.g. zai/glm-4.6,
# deepseek/deepseek-chat). Verified against opencode 1.19.6.

adapter_spawn() {
  # <agent> — verify the CLI is present. opencode run is headless by default;
  # there is no hidden interactive mode to guard against.
  command -v opencode >/dev/null 2>&1 || {
    log_warn "opencode not found on PATH"
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

  # --auto auto-approves tool permissions so the run finishes unattended; it is
  # safe here because every task runs in its own git worktree and orchestra
  # gates destructive actions (push/deploy/...) itself at MERGE.
  set -- opencode run --format json --auto
  [ -n "$_model" ] && set -- "$@" --model "$_model"
  set -- "$@" "$(cat "$_spec")"
  run_to_exit_dispatch "$_task" "$_wd" "$@"
}

adapter_wait() {
  run_to_exit_wait "$2" "${3:-0}"
}

adapter_capability() {
  # Generic coder; refine per project via the agent's `skills` in the config.
  printf '%s\n' backend api frontend algo refactor
}
