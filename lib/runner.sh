# shellcheck shell=sh
# VERIFY layer: runs a task's done_when (tests, typecheck, build, commands) for
# real, in its worktree. Agents never declare themselves done — the runner does.
# Writes .bus/verify/<task>.json (schemas/verify.schema.json).

# _runner_run <workdir> <cmd> — run cmd in workdir, print its exit code.
_runner_run() {
  _rr_wd=$1
  _rr_cmd=$2
  (
    cd "$_rr_wd" 2>/dev/null || exit 127
    sh -c "$_rr_cmd" >/dev/null 2>&1
  )
  printf '%s\n' "$?"
}

# _runner_check_json <name> <cmd> <exit> — one check object.
_runner_check_json() {
  _rc_exit=$3
  jq -nc --arg n "$1" --arg c "$2" --argjson e "$_rc_exit" \
    '{name:$n, cmd:$c, exit:$e, passed:($e==0)}'
}

# runner_verify <task-id> <workdir> — evaluate done_when; write the report and
# return 0 only if every check passed.
runner_verify() {
  _task=$1
  _wd=$2
  _checks=$(mktemp)

  # tests: done_when.tests_pass through stack.test_one, {files} -> file list.
  _tests=$(plan_task "$_task" '.done_when.tests_pass[]?' | tr '\n' ' ')
  _tests=${_tests% }
  if [ -n "$_tests" ]; then
    _tmpl=$(config_get '.stack.test_one')
    _pre=${_tmpl%%\{files\}*}
    _post=${_tmpl#*\{files\}}
    _cmd=$_pre$_tests$_post
    _e=$(_runner_run "$_wd" "$_cmd")
    _runner_check_json tests "$_cmd" "$_e" >>"$_checks"
  fi

  # typecheck
  if [ "$(plan_task "$_task" '.done_when.typecheck // false')" = "true" ]; then
    _cmd=$(config_get '.stack.typecheck // empty')
    [ -n "$_cmd" ] || die "task $_task wants typecheck but stack.typecheck is unset"
    _e=$(_runner_run "$_wd" "$_cmd")
    _runner_check_json typecheck "$_cmd" "$_e" >>"$_checks"
  fi

  # build
  if [ "$(plan_task "$_task" '.done_when.build // false')" = "true" ]; then
    _cmd=$(config_get '.stack.build // empty')
    [ -n "$_cmd" ] || die "task $_task wants build but stack.build is unset"
    _e=$(_runner_run "$_wd" "$_cmd")
    _runner_check_json build "$_cmd" "$_e" >>"$_checks"
  fi

  # extra commands
  plan_task "$_task" '.done_when.commands[]?' | while IFS= read -r _cmd; do
    [ -n "$_cmd" ] || continue
    _e=$(_runner_run "$_wd" "$_cmd")
    _runner_check_json command "$_cmd" "$_e" >>"$_checks"
  done

  _vdir=$(bus_dir)/verify
  mkdir -p "$_vdir"
  jq -s --arg t "$_task" --arg at "$(now_iso)" \
    '{task:$t, passed:(all(.[]; .passed)), checks:., verified_at:$at}' \
    "$_checks" >"$_vdir/$_task.json"
  rm -f "$_checks"

  [ "$(jq -r '.passed' "$_vdir/$_task.json")" = "true" ]
}

# runner_integration — milestone integration build (build + smoke + health).
# Deferred to the pool milestone (roadmap step 5).
runner_integration() { not_implemented runner_integration; }
