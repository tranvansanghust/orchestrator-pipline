# shellcheck shell=sh
# VERIFY layer: runs a task's done_when (tests, typecheck, build) for real.
# Agents never declare themselves done — the runner does.

# runner_verify <task-id> <worktree> — evaluate done_when; write
# .bus/verify/<task-id>.json and return 0 only if everything passed.
runner_verify() { not_implemented runner_verify; }

# runner_integration — milestone integration build: build + smoke test +
# dev server health check, in its own sandbox pane.
runner_integration() { not_implemented runner_integration; }
