# shellcheck shell=sh
# Path back to the human. "Not sure" always means STOP, never GO; an
# escalated task is never auto-accepted, it only blocks itself and its
# dependents while the rest of the DAG keeps running.

# escalation_check <task-id> <verdict-file> — apply the hard rules
# (always_human areas, abnormal diff size, reject rounds >= K, green verify
# but reviewer concerns) on top of the reviewer's own confidence; return 0
# if the task must escalate.
escalation_check() { not_implemented escalation_check; }

# escalation_open <task-id> <inbox|tui|gate> <reason> — open an escalation
# on the given channel and log it.
escalation_open() { not_implemented escalation_open; }

# escalation_resolve <task-id> <accept|reject|amend-spec> [message] —
# `orchestra resolve`. amend-spec patches SRS, test plan and traceability,
# then re-dispatches the task.
escalation_resolve() { not_implemented resolve; }
