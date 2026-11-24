# shellcheck shell=sh
# Adapter: mock — the reference run-to-exit adapter. No network, deterministic.
# Use it to exercise the pool, scheduler and runner without spending API calls,
# and as the clearest example of the four-function interface.
#
# Behaviour: by default it writes a line into the worktree and exits 0. Set
# ORCHESTRA_MOCK_CMD to a shell snippet to make it do (or fail) whatever a test
# needs; it runs in the task worktree.

adapter_spawn() {
  # Nothing to start; always ready.
  return 0
}

adapter_dispatch() {
  # <agent> <task-id> <spec-file> <workdir>
  _task=$2
  _spec=$3
  _wd=$4
  # The snippet runs in the child shell; $1/$2/ORCHESTRA_MOCK_CMD expand there.
  # shellcheck disable=SC2016
  run_to_exit_dispatch "$_task" "$_wd" sh -c '
    if [ -n "$ORCHESTRA_MOCK_CMD" ]; then
      eval "$ORCHESTRA_MOCK_CMD"
    else
      printf "mock handled task %s from spec %s\n" "$1" "$2"
    fi
  ' mock "$_task" "$_spec"
}

adapter_wait() {
  # <agent> <task-id> [timeout-seconds]
  run_to_exit_wait "$2" "${3:-0}"
}

adapter_capability() {
  # <agent> — default skills when the config omits them.
  printf '%s\n' backend api frontend algo refactor
}
