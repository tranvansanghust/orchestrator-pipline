# shellcheck shell=sh
# Task lifecycle. Only the edges below are legal; every transition is guarded
# and appended to .bus/log.jsonl. A task with no state file is DRAFT.
#
#   DRAFT -> DISPATCHED -> IN_PROGRESS -> SUBMITTED -> VERIFY
#   VERIFY      -> REVIEW (pass) | IN_PROGRESS (fail, retry) | BLOCKED
#   REVIEW      -> MERGED (accept) | DRAFT (reject, back to the agent) | ESCALATED
#   MERGED      -> DONE
#   ESCALATED   -> MERGED | DRAFT                    (orchestra resolve, step 6)
#   DRAFT, DISPATCHED, IN_PROGRESS -> BLOCKED        (no agent, setup, dispatch)

_SM_EDGES="DRAFT:DISPATCHED DRAFT:BLOCKED DISPATCHED:IN_PROGRESS DISPATCHED:BLOCKED
IN_PROGRESS:SUBMITTED IN_PROGRESS:BLOCKED SUBMITTED:VERIFY VERIFY:REVIEW
VERIFY:IN_PROGRESS VERIFY:BLOCKED REVIEW:MERGED REVIEW:DRAFT REVIEW:ESCALATED
MERGED:DONE ESCALATED:MERGED ESCALATED:DRAFT"

_sm_file() { printf '%s/tasks/%s.json\n' "$(bus_dir)" "$1"; }

# task_get <task-id> <jq-path> — read the task state (defaults for a new task).
task_get() {
  _gf=$(_sm_file "$1")
  if [ -f "$_gf" ]; then
    jq -r "$2" "$_gf"
  else
    jq -nr --arg t "$1" '{id: $t, state: "DRAFT", attempt: 0, verify_rounds: 0, reject_rounds: 0}' | jq -r "$2"
  fi
}

# task_update <task-id> <jq-filter> [jq-args...] — update the task state file.
task_update() {
  _uf=$(_sm_file "$1")
  _uflt=$2
  mkdir -p "$(dirname "$_uf")"
  if [ ! -f "$_uf" ]; then
    jq -n --arg t "$1" '{id: $t, state: "DRAFT", attempt: 0, verify_rounds: 0, reject_rounds: 0}' >"$_uf"
  fi
  shift 2
  jq "$@" "$_uflt" "$_uf" >"$_uf.tmp" && mv "$_uf.tmp" "$_uf"
}

# sm_state <task-id> — print the current state of a task.
sm_state() { task_get "$1" '.state'; }

# sm_can_transition <from> <to> — return 0 if the edge is legal.
sm_can_transition() {
  # shellcheck disable=SC2086 # word-split the edge list on purpose
  for _e in $_SM_EDGES; do
    [ "$_e" = "$1:$2" ] && return 0
  done
  return 1
}

# sm_transition <task-id> <to> <reason> — guarded transition + audit log.
sm_transition() {
  _from=$(sm_state "$1")
  sm_can_transition "$_from" "$2" || die "illegal transition for $1: $_from -> $2"
  # shellcheck disable=SC2016 # jq variables
  task_update "$1" '.state = $s | .reason = $r | .updated_at = $at' \
    --arg s "$2" --arg r "$3" --arg at "$(now_iso)"
  bus_log "$(jq -nc --arg t "$1" --arg f "$_from" --arg s "$2" --arg r "$3" \
    '{event: "transition", task: $t, from: $f, to: $s, reason: $r}')"
  printf '  %-4s %-11s -> %-11s %s\n' "$1" "$_from" "$2" "$3"
}

# status_main — `orchestra status`: task table, FR status, open escalations.
status_main() {
  plan_path >/dev/null
  printf '%-5s %-11s %-10s %-6s %-6s %s\n' TASK STATE AGENT VERIFY REJECT REASON
  for _t in $(plan_get '.tasks[].id'); do
    printf '%-5s %-11s %-10s %-6s %-6s %s\n' "$_t" "$(sm_state "$_t")" \
      "$(task_get "$_t" '.agent // "-"')" "$(task_get "$_t" '.verify_rounds')" \
      "$(task_get "$_t" '.reject_rounds')" "$(task_get "$_t" '.reason // ""')"
  done
  _ts=$(bus_dir)/traceability.status.json
  if [ -f "$_ts" ]; then
    printf '\nRequirements:\n'
    jq -r 'to_entries[] | "  \(.key)  \(.value.status)  \(.value.desc)"' "$_ts"
  fi
  set -- "$(bus_dir)"/escalations/*.md
  if [ -e "$1" ]; then
    printf '\nNeeds a human:\n'
    for _e in "$@"; do
      printf '  %s\n' "${_e#"$(project_root)"/}"
    done
  fi
}
