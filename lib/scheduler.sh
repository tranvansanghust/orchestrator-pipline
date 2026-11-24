# shellcheck shell=sh
# Walks the plan.json DAG in plan order and matches tasks to agents by skill.
# The daemon runs up to execution.max_parallel tasks at once; each agent works
# on one task at a time (ADR-0012).

# States in which a task still has work the daemon can do.
_SCHED_ACTIVE="DRAFT DISPATCHED IN_PROGRESS SUBMITTED VERIFY REVIEW MERGED"

# _sched_in <item> <newline-separated list>
_sched_in() { printf '%s\n' "$2" | grep -qxF -- "$1"; }

# scheduler_next [exclude-tasks] [busy-agents] — the first active task in plan
# order whose deps are all DONE, is not excluded, and has a free agent.
# Prints "<task> <agent>", or "<task> -" when no configured agent has the
# task's skill (the task then blocks). A task left mid-flow by a stopped run
# is picked up again here, with the agent it already had.
scheduler_next() {
  _ex=${1:-}
  _busy=${2:-}
  for _t in $(plan_get '.tasks[].id'); do
    if [ -n "$_ex" ] && _sched_in "$_t" "$_ex"; then continue; fi
    case " $_SCHED_ACTIVE " in
      *" $(sm_state "$_t") "*) ;;
      *) continue ;;
    esac
    _ready=1
    for _d in $(plan_task "$_t" '.deps[]?'); do
      if [ "$(sm_state "$_d")" != DONE ]; then
        _ready=0
        break
      fi
    done
    [ "$_ready" = 1 ] || continue
    _a=$(task_get "$_t" '.agent // empty')
    if [ -n "$_a" ]; then
      if [ -n "$_busy" ] && _sched_in "$_a" "$_busy"; then continue; fi
      printf '%s %s\n' "$_t" "$_a"
      return 0
    fi
    _cands=$(pool_agents_for_skill "$(plan_task "$_t" '.skill')")
    if [ -z "$_cands" ]; then
      printf '%s -\n' "$_t"
      return 0
    fi
    for _c in $_cands; do
      if [ -z "$_busy" ] || ! _sched_in "$_c" "$_busy"; then
        printf '%s %s\n' "$_t" "$_c"
        return 0
      fi
    done
  done
  return 0
}

# scheduler_pick_agent <task-id> — first agent advertising the task's skill.
scheduler_pick_agent() {
  pool_agents_for_skill "$(plan_task "$1" '.skill')" | head -n 1
}
