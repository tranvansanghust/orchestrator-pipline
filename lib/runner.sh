# shellcheck shell=sh
# VERIFY layer: runs a task's done_when (tests, typecheck, build, commands) for
# real, in its worktree. Agents never declare themselves done — the runner does.
# Writes .bus/verify/<task>.json (schemas/verify.schema.json) and keeps each
# check's output in .bus/verify/<task>/<n>-<name>.log.

# runner_plan <task-id> — the checks done_when asks for, one per line as
# "<name><TAB><command>". A check whose stack command is unset has an empty
# command; runner_verify records it as failed.
runner_plan() {
  _tests=$(plan_task "$1" '.done_when.tests_pass[]?' | tr '\n' ' ')
  _tests=${_tests% }
  if [ -n "$_tests" ]; then
    _tmpl=$(config_get '.stack.test_one')
    printf 'tests\t%s%s%s\n' "${_tmpl%%\{files\}*}" "$_tests" "${_tmpl#*\{files\}}"
  fi
  for _k in typecheck build; do
    if [ "$(plan_task "$1" ".done_when.$_k // false")" = "true" ]; then
      printf '%s\t%s\n' "$_k" "$(config_get ".stack.$_k // empty")"
    fi
  done
  plan_task "$1" '.done_when.commands[]?' | while IFS= read -r _c; do
    [ -n "$_c" ] && printf 'command\t%s\n' "$_c"
  done
  return 0
}

# runner_verify <task-id> <workdir> — evaluate done_when; write the report and
# return 0 only if every check passed.
runner_verify() {
  _task=$1
  _wd=$2
  _vdir=$(bus_dir)/verify
  mkdir -p "$_vdir/$_task"
  rm -f "$_vdir/$_task"/*.log
  _checks=$(mktemp)
  _plan=$(mktemp)
  runner_plan "$_task" >"$_plan"
  _n=0
  _tab=$(printf '\t')
  while IFS="$_tab" read -r _name _cmd; do
    _n=$((_n + 1))
    _log=$_vdir/$_task/$_n-$_name.log
    if [ -z "$_cmd" ]; then
      log_warn "task $_task wants $_name but stack.$_name is unset"
      printf 'stack.%s is unset in orchestra.config.json\n' "$_name" >"$_log"
      _cmd="(stack.$_name is unset)"
      _e=127
    else
      ( cd "$_wd" 2>/dev/null || exit 127; sh -c "$_cmd" ) >"$_log" 2>&1 && _e=0 || _e=$?
    fi
    jq -nc --arg n "$_name" --arg c "$_cmd" --argjson e "$_e" --arg l "$_log" \
      '{name: $n, cmd: $c, exit: $e, passed: ($e == 0), log: $l}' >>"$_checks"
  done <"$_plan"

  jq -s --arg t "$_task" --arg at "$(now_iso)" \
    '{task: $t, passed: (length > 0 and all(.[]; .passed)), checks: ., verified_at: $at}' \
    "$_checks" >"$_vdir/$_task.json"
  rm -f "$_checks" "$_plan"
  [ "$(jq -r '.passed' "$_vdir/$_task.json")" = "true" ]
}

# runner_integration — milestone integration build (build + smoke + health).
# Deferred to the pool milestone (roadmap step 5).
runner_integration() { not_implemented runner_integration; }
