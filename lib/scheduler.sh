# shellcheck shell=sh
# Walks the plan.json DAG: picks tasks whose deps are DONE and matches them
# to an agent by skill.

# scheduler_ready_tasks — print ids of DRAFT tasks whose deps are all DONE.
scheduler_ready_tasks() { not_implemented scheduler_ready_tasks; }

# scheduler_pick_agent <task-id> — print the agent name to run the task on.
scheduler_pick_agent() { not_implemented scheduler_pick_agent; }

# scheduler_dag_drained — return 0 when no runnable or running task is left.
scheduler_dag_drained() { not_implemented scheduler_dag_drained; }
