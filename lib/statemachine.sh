# shellcheck shell=sh
# Task lifecycle. Only the edges below are legal; every transition is guarded
# and appended to .bus/log.jsonl.
#
#   DRAFT -> DISPATCHED -> IN_PROGRESS -> SUBMITTED -> VERIFY
#   VERIFY  -> IN_PROGRESS (fail, retry) | BLOCKED (retries exhausted) | REVIEW
#   REVIEW  -> MERGED (accept) | DRAFT (reject, v2 + feedback) | ESCALATED
#   MERGED  -> DONE
#   ESCALATED -> MERGED | DRAFT (after /resolve)

# sm_state <task-id> — print the current state of a task.
sm_state() { not_implemented sm_state; }

# sm_can_transition <from> <to> — return 0 if the edge is legal.
sm_can_transition() { not_implemented sm_can_transition; }

# sm_transition <task-id> <to> <reason> — guarded transition + audit log.
sm_transition() { not_implemented sm_transition; }

# status_main — `orchestra status`: task table and open escalations.
status_main() { not_implemented status; }
