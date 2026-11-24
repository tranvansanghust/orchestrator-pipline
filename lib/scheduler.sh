# shellcheck shell=sh
# Walks the plan.json DAG in plan order and matches tasks to agents by skill.
# Tasks run one at a time (roadmap step 4); the pool milestone adds parallelism.

# States in which a task still has work the daemon can do.
_SCHED_ACTIVE="DRAFT DISPATCHED IN_PROGRESS SUBMITTED VERIFY REVIEW MERGED"

# scheduler_next — the first active task whose deps are all DONE, or nothing.
# A task left mid-flow by a stopped run is picked up again here.
scheduler_next() {
  for _t in $(plan_get '.tasks[].id'); do
    _st=$(sm_state "$_t")
    case " $_SCHED_ACTIVE " in
      *" $_st "*) ;;
      *) continue ;;
    esac
    _ready=1
    for _d in $(plan_task "$_t" '.deps[]?'); do
      if [ "$(sm_state "$_d")" != DONE ]; then
        _ready=0
        break
      fi
    done
    if [ "$_ready" = 1 ]; then
      printf '%s\n' "$_t"
      return 0
    fi
  done
}

# scheduler_pick_agent <task-id> — first agent advertising the task's skill.
scheduler_pick_agent() {
  pool_agents_for_skill "$(plan_task "$1" '.skill')" | head -n 1
}
