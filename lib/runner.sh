# shellcheck shell=sh
# VERIFY layer: runs a task's done_when (tests, typecheck, build, commands) for
# real, in its worktree. Agents never declare themselves done — the runner does.
# Writes .bus/verify/<task>.json (schemas/verify.schema.json) and keeps each
# check's output in .bus/verify/<task>/<n>-<name>.log.
#
# In a workspace (ADR-0013) each check runs in the repo it belongs to, with that
# repo's stack: tests_pass is grouped by owning repo and passed repo-relative;
# typecheck and build run in every repo of the task that defines them;
# commands run at the top of the worktree.

# runner_plan <task-id> — the checks done_when asks for, one per line as
# "<name><TAB><repo><TAB><command>" (repo "-" for commands: top of the
# worktree). A check whose stack command is unset has an empty command;
# runner_verify records it as failed.
runner_plan() {
  _tab=$(printf '\t')
  _owned=$(plan_task "$1" '.done_when.tests_pass[]?' | while IFS= read -r _tf; do
    _to=$(repo_of "$_tf")
    _tp=$(repo_path "$_to")
    printf '%s\t%s\n' "$_to" "${_tf#"$_tp"/}"
  done)
  for _r in $(repo_names); do
    _tests=$(printf '%s\n' "$_owned" | awk -F "$_tab" -v r="$_r" '$1 == r { printf "%s ", $2 }')
    _tests=${_tests% }
    [ -n "$_tests" ] || continue
    _tmpl=$(repo_stack "$_r" test_one)
    printf 'tests\t%s\t%s%s%s\n' "$_r" "${_tmpl%%\{files\}*}" "$_tests" "${_tmpl#*\{files\}}"
  done
  for _k in typecheck build; do
    [ "$(plan_task "$1" ".done_when.$_k // false")" = "true" ] || continue
    _any=0
    for _r in $(task_repos "$1"); do
      _c=$(repo_stack "$_r" "$_k")
      [ -n "$_c" ] || continue
      printf '%s\t%s\t%s\n' "$_k" "$_r" "$_c"
      _any=1
    done
    [ "$_any" = 1 ] || printf '%s\t%s\t\n' "$_k" "$(task_repos "$1" | head -n 1)"
  done
  plan_task "$1" '.done_when.commands[]?' | while IFS= read -r _c; do
    [ -n "$_c" ] && printf 'command\t-\t%s\n' "$_c"
  done
  return 0
}

# runner_verify <task-id> <workdir> [foreign-file] — evaluate done_when in the
# worktree; write the report and return 0 only if every check passed. A
# non-empty foreign-file ("<repo> <path>" lines from worktree_foreign) adds a
# failed scope check listing the discarded changes.
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
  if [ -s "${3:-}" ]; then
    _n=1
    _log=$_vdir/$_task/$_n-scope.log
    {
      printf 'The task may change only these repos: %s.\n' "$(task_repos "$_task" | paste -sd, -)"
      printf 'Its changes to these files were discarded:\n\n'
      cut -d' ' -f2- "$3" | sed 's/^/- /'
    } >"$_log"
    jq -nc --arg l "$_log" \
      '{name: "scope", cmd: "changes outside the task'"'"'s repos (discarded)", exit: 1, passed: false, log: $l}' >>"$_checks"
  fi
  _tab=$(printf '\t')
  while IFS="$_tab" read -r _name _repo _cmd; do
    _n=$((_n + 1))
    _log=$_vdir/$_task/$_n-$_name.log
    _dir=$_wd
    if [ "$_repo" != - ] && [ "$(repo_path "$_repo")" != . ]; then
      _dir=$_wd/$(repo_path "$_repo")
    fi
    if [ -z "$_cmd" ]; then
      log_warn "task $_task wants $_name but stack.$_name is unset"
      printf 'stack.%s is unset in orchestra.config.json\n' "$_name" >"$_log"
      _cmd="(stack.$_name is unset)"
      _e=127
    else
      ( cd "$_dir" 2>/dev/null || exit 127; sh -c "$_cmd" ) >"$_log" 2>&1 && _e=0 || _e=$?
    fi
    jq -nc --arg n "$_name" --arg r "$_repo" --arg c "$_cmd" --argjson e "$_e" --arg l "$_log" \
      '{name: $n} + (if $r == "-" then {} else {repo: $r} end)
       + {cmd: $c, exit: $e, passed: ($e == 0), log: $l}' >>"$_checks"
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
