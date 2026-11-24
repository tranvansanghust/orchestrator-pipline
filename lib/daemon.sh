# shellcheck shell=sh
# Phase 2 (ADR-0007, ADR-0010). `orchestra go` approves and freezes the design,
# then runs the plan one task at a time:
#
#   DRAFT       pick agent by skill, create worktree (+ stack.setup), write prompt
#   DISPATCHED  hand the prompt to the agent
#   IN_PROGRESS wait for it (execution.agent_timeout_s)
#   VERIFY      runner checks done_when; fail -> feedback + retry, up to
#               max_verify_rounds, then BLOCKED
#   REVIEW      reviewer + confirmer + hard rules; ACCEPT -> commit + merge into
#               orchestra/run; REJECT -> back to the agent with the fixes, up to
#               max_reject_rounds, then ESCALATED; ESCALATE -> inbox
#   MERGED      remove the worktree, DONE, dependents unlock
#
# Every step is persisted in .bus/, so a stopped run resumes where it was.
# Destructive actions (push, deploy, ...) are never taken.

# --- design freeze -----------------------------------------------------------

# _go_freeze <profile> — mark the plan approved and hash the design.
_go_freeze() {
  _root=$(project_root)
  _plan=$(plan_path)
  jq '.approved = true' "$_plan" >"$_plan.tmp" && mv "$_plan.tmp" "$_plan"
  mkdir -p "$(bus_dir)"
  (
    cd "$_root" || exit 1
    { find docs -type f | LC_ALL=C sort; printf 'plan.json\ntraceability.json\n'; } \
      | while IFS= read -r _f; do
          [ -f "$_f" ] || continue
          jq -nc --arg f "$_f" --arg h "$(sha256 "$_f")" '{($f): $h}'
        done
  ) | jq -s --arg at "$(now_iso)" --arg p "$1" \
    '{frozen_at: $at, profile: $p, files: add}' >"$(bus_dir)/frozen.json"
  printf '\nApproved: plan.json marked approved, %s artifacts frozen in .bus/frozen.json.\n' \
    "$(jq '.files | length' "$(bus_dir)/frozen.json")"
}

# _go_drift — design files changed, deleted or added since the freeze.
_go_drift() {
  _fz=$(bus_dir)/frozen.json
  (
    cd "$(project_root)" || exit 1
    _tab=$(printf '\t')
    jq -r '.files | to_entries[] | "\(.key)\t\(.value)"' "$_fz" | while IFS="$_tab" read -r _f _h; do
      if [ ! -f "$_f" ]; then
        printf '%s (deleted)\n' "$_f"
      elif [ "$(sha256 "$_f")" != "$_h" ]; then
        printf '%s (changed)\n' "$_f"
      fi
    done
    find docs -type f | LC_ALL=C sort | while IFS= read -r _f; do
      jq -e --arg f "$_f" '.files | has($f)' "$_fz" >/dev/null || printf '%s (new)\n' "$_f"
    done
  )
}

# go_main [--profile P] [--refreeze] [--no-run] — `orchestra go`.
go_main() {
  _profile=""
  _refreeze=0
  _run=1
  while [ $# -gt 0 ]; do
    case $1 in
      --profile)
        [ $# -ge 2 ] || { printf 'orchestra go: --profile needs a value\n' >&2; exit "$ORCHESTRA_EXIT_USAGE"; }
        _profile=$2
        shift 2
        ;;
      --profile=*) _profile=${1#*=}; shift ;;
      --refreeze) _refreeze=1; shift ;;
      --no-run) _run=0; shift ;;
      *)
        printf 'orchestra go: unknown option: %s\n' "$1" >&2
        exit "$ORCHESTRA_EXIT_USAGE"
        ;;
    esac
  done
  [ -n "$_profile" ] || _profile=$(config_get '.profile')

  if [ -f "$(bus_dir)/frozen.json" ] && [ "$(plan_get '.approved')" = true ] && [ "$_refreeze" = 0 ]; then
    _drift=$(_go_drift)
    if [ -n "$_drift" ]; then
      printf 'The design changed since it was frozen:\n'
      printf '%s\n' "$_drift" | sed 's/^/  /'
      die "re-run with --refreeze to accept the changes (the readiness check runs again)"
    fi
    printf 'Design unchanged since %s; resuming.\n' "$(jq -r '.frozen_at' "$(bus_dir)/frozen.json")"
  else
    readiness_check "$_profile" \
      || die "readiness check failed; fix the gaps above, then run orchestra go again"
    _go_freeze "$_profile"
  fi

  if [ "$_run" = 0 ]; then
    printf 'Run `orchestra go` to start phase 2.\n'
    return 0
  fi
  worktree_run_init
  daemon_loop
}

# --- per-task helpers --------------------------------------------------------

_dm_tdir() { printf '%s/tasks/%s\n' "$(bus_dir)" "$1"; }
_dm_stop_requested() { [ -f "$(bus_dir)/stop" ]; }

# _dm_prompt <task-id> — write the next agent prompt; print its path.
_dm_prompt() {
  _pt=$1
  _pdir=$(_dm_tdir "$_pt")
  mkdir -p "$_pdir"
  _pa=$(($(task_get "$_pt" '.attempt') + 1))
  # shellcheck disable=SC2016 # jq variables
  task_update "$_pt" '.attempt = $a' --argjson a "$_pa"
  _pout=$_pdir/prompt-$_pa.md
  _tab=$(printf '\t')
  {
    printf '# Task %s: %s\n\n' "$_pt" "$(plan_task "$_pt" '.desc')"
    printf 'You are implementing one task of a larger, already-designed plan, in this git\n'
    printf 'worktree (your current directory). Other tasks are handled separately; stay\n'
    printf 'within this one. The design documents are in docs/ (contracts in\n'
    printf 'docs/04-api-spec.yaml, test plan in docs/06-test-plan.md).\n\n'
    printf '## Definition of done\n\n'
    printf 'You do not decide when you are done. Afterwards the orchestrator runs:\n\n'
    runner_plan "$_pt" | while IFS="$_tab" read -r _n _c; do
      printf -- '- %s: `%s`\n' "$_n" "${_c:-(not configured)}"
    done
    printf '\nWrite or update the test files named above so they assert the acceptance\n'
    printf 'criteria below and the cases in the test plan (happy path and edge cases),\n'
    printf 'then make them pass. Tests that pass without checking anything will be rejected.\n\n'
    _ps=$(plan_task "$_pt" '.scope[]?')
    if [ -n "$_ps" ]; then
      printf '## Files you may change\n\n'
      printf '%s\n' "$_ps" | sed 's/^/- /'
      printf -- '- the test files above\n\n'
    fi
    printf '## Requirements\n\n'
    jq -r --arg t "$_pt" 'to_entries[] | select(.value.tasks | index($t))
      | "- \(.key): \(.value.desc). Acceptance: \(.value.acceptance)"' \
      "$(project_root)/traceability.json" 2>/dev/null || true
    printf '\n## Spec\n\n'
    _spec=$(project_root)/$(plan_task "$_pt" '.spec_file')
    if [ -f "$_spec" ]; then cat "$_spec"; fi
    if [ -f "$_pdir/feedback.md" ]; then
      printf '\n'
      cat "$_pdir/feedback.md"
    fi
    printf '\nYou may commit your work; anything left uncommitted is committed for you.\n'
  } >"$_pout"
  rm -f "$_pdir/feedback.md"
  printf '%s\n' "$_pout"
}

# _dm_dispatch <task-id> — write the prompt and start the agent.
_dm_dispatch() {
  _dp=$(_dm_prompt "$1")
  ( pool_call "$(task_get "$1" '.agent')" dispatch "$1" "$_dp" "$(task_get "$1" '.worktree')" )
}

# _dm_agent_running <task-id> — the agent's run has not finished.
_dm_agent_running() {
  _adir=$(bus_dir)/agents
  [ -f "$_adir/$1.exit" ] && return 1
  [ -f "$_adir/$1.pid" ] && kill -0 "$(cat "$_adir/$1.pid")" 2>/dev/null
}

# _dm_feedback_verify <task-id> — tell the agent what failed.
_dm_feedback_verify() {
  _ft=$1
  {
    printf '## Previous attempt failed verification\n\n'
    if [ "$(task_get "$_ft" '.agent_rc // 0')" = 124 ]; then
      printf 'Your last run hit the time limit (%ss) and was stopped.\n\n' \
        "$(config_get '.execution.agent_timeout_s // 1800')"
    fi
    printf 'The orchestrator ran these checks after your last attempt:\n\n'
    jq -r '.checks[] | select(.passed | not) | "\(.name)\t\(.cmd)\t\(.exit)\t\(.log)"' \
      "$(bus_dir)/verify/$_ft.json" | while IFS="$(printf '\t')" read -r _n _c _e _l; do
        printf '### %s failed (exit %s): `%s`\n\n```\n' "$_n" "$_e" "$_c"
        if [ -f "$_l" ]; then tail -n 60 "$_l"; fi
        printf '```\n\n'
      done
  } >"$(_dm_tdir "$_ft")/feedback.md"
}

# _dm_last_round <task-id> — directory of the latest review round.
_dm_last_round() {
  _lr=1
  while [ -d "$(bus_dir)/review/$1/round-$((_lr + 1))" ]; do
    _lr=$((_lr + 1))
  done
  printf '%s/review/%s/round-%s\n' "$(bus_dir)" "$1" "$_lr"
}

# _dm_feedback_reject <task-id> — pass the reviewer's fixes to the agent.
_dm_feedback_reject() {
  _rd=$(_dm_last_round "$1")
  {
    printf '## The reviewer rejected your last attempt\n\n'
    jq -r '.summary' "$_rd/verdict.json"
    printf '\nMake these changes:\n\n'
    jq -r '.fixes_requested[]? | "- \(.)"' "$_rd/verdict.json"
    _cn=$(jq -r '.concerns[]? | "- [\(.severity)] \(.detail)"' "$_rd/verdict.json")
    if [ -n "$_cn" ]; then
      printf '\nConcerns:\n\n%s\n' "$_cn"
    fi
  } >"$(_dm_tdir "$1")/feedback.md"
}

# _dm_block <task-id> <kind> <reason> / _dm_escalate <task-id> <kind> <reason>
_dm_block() {
  sm_transition "$1" BLOCKED "$3"
  escalation_open "$1" "$2" "$3"
}
_dm_escalate() {
  sm_transition "$1" ESCALATED "$3"
  escalation_open "$1" "$2" "$3"
}

# _dm_review_reason <task-id> — why the latest review escalated.
_dm_review_reason() {
  _rd=$(_dm_last_round "$1")
  _rr=$(jq -r '.reasons | join("; ")' "$_rd/decision.json" 2>/dev/null || true)
  if [ -z "$_rr" ]; then
    _rr="reviewer escalated: $(jq -r '[.summary, (.question_for_human // empty)] | join(" ")' "$_rd/verdict.json" 2>/dev/null || echo "see $_rd")"
  fi
  printf '%s\n' "$_rr"
}

# _dm_run_task <task-id> — drive one task from its current state until it is
# DONE, BLOCKED or ESCALATED, or a stop is requested.
_dm_run_task() {
  _t=$1
  _maxv=$(config_get '.escalation.max_verify_rounds // 3')
  _maxr=$(config_get '.escalation.max_reject_rounds // 3')
  mkdir -p "$(_dm_tdir "$_t")"
  while :; do
    if _dm_stop_requested; then return 0; fi
    _agent=$(task_get "$_t" '.agent // empty')
    case $(sm_state "$_t") in
      DRAFT)
        if [ -z "$_agent" ]; then
          _agent=$(scheduler_pick_agent "$_t")
          if [ -z "$_agent" ]; then
            _dm_block "$_t" setup "no agent in orchestra.config.json advertises skill \"$(plan_task "$_t" '.skill')\""
            return 0
          fi
          # shellcheck disable=SC2016 # jq variables
          task_update "$_t" '.agent = $a' --arg a "$_agent"
        fi
        if ! ( pool_spawn "$_agent" ) >/dev/null 2>&1; then
          _dm_block "$_t" agent "agent $_agent is not available (its adapter's spawn check failed)"
          return 0
        fi
        _wt=$(_wt_dir "$_t")
        if [ ! -d "$_wt" ]; then
          if ! ( worktree_create "$_t" ) >/dev/null 2>&1; then
            _dm_block "$_t" setup "could not create the worktree .worktrees/$_t"
            return 0
          fi
          _setup=$(config_get '.stack.setup // empty')
          if [ -n "$_setup" ]; then
            if ! ( cd "$_wt" && sh -c "$_setup" ) >"$(_dm_tdir "$_t")/setup.log" 2>&1; then
              _dm_block "$_t" setup "stack.setup failed (see .bus/tasks/$_t/setup.log)"
              return 0
            fi
          fi
        fi
        sm_transition "$_t" DISPATCHED "agent $_agent"
        ;;
      DISPATCHED)
        if ! _dm_dispatch "$_t"; then
          _dm_block "$_t" agent "could not start agent $_agent"
          return 0
        fi
        sm_transition "$_t" IN_PROGRESS "attempt $(task_get "$_t" '.attempt')"
        ;;
      IN_PROGRESS)
        if [ ! -f "$(bus_dir)/agents/$_t.exit" ] && ! _dm_agent_running "$_t"; then
          # The run was interrupted (stopped daemon): start it again.
          if ! _dm_dispatch "$_t"; then
            _dm_block "$_t" agent "could not restart agent $_agent"
            return 0
          fi
        fi
        if ( pool_call "$_agent" wait "$_t" "$(config_get '.execution.agent_timeout_s // 1800')" ); then
          _rc=0
        else
          _rc=$?
        fi
        # shellcheck disable=SC2016 # jq variables
        task_update "$_t" '.agent_rc = $rc' --argjson rc "$_rc"
        if [ "$_rc" = 124 ]; then
          sm_transition "$_t" SUBMITTED "agent timed out"
        else
          sm_transition "$_t" SUBMITTED "agent finished"
        fi
        ;;
      SUBMITTED)
        sm_transition "$_t" VERIFY "running done_when"
        ;;
      VERIFY)
        if ( runner_verify "$_t" "$(task_get "$_t" '.worktree')" ) >/dev/null 2>&1; then
          sm_transition "$_t" REVIEW "verify passed"
        else
          _n=$(($(task_get "$_t" '.verify_rounds') + 1))
          # shellcheck disable=SC2016 # jq variables
          task_update "$_t" '.verify_rounds = $n' --argjson n "$_n"
          if [ "$_n" -ge "$_maxv" ]; then
            _dm_block "$_t" verify "VERIFY failed $_n times (max_verify_rounds = $_maxv)"
            return 0
          fi
          _dm_feedback_verify "$_t"
          if ! _dm_dispatch "$_t"; then
            _dm_block "$_t" agent "could not restart agent $_agent"
            return 0
          fi
          sm_transition "$_t" IN_PROGRESS "verify failed ($_n/$_maxv), retrying"
        fi
        ;;
      REVIEW)
        if _v=$(review_run "$_t" "$(task_get "$_t" '.worktree')" 2>"$(_dm_tdir "$_t")/review.err"); then :; else _v=ERROR; fi
        case $_v in
          ACCEPT)
            if daemon_integrate "$_t" >/dev/null 2>&1; then _irc=0; else _irc=$?; fi
            case $_irc in
              0) sm_transition "$_t" MERGED "accepted, merged into orchestra/run" ;;
              2)
                _dm_escalate "$_t" merge "accepted, but it conflicts with work merged into orchestra/run meanwhile"
                return 0
                ;;
              3)
                _dm_escalate "$_t" integration "accepted, but VERIFY fails once the work merged into orchestra/run meanwhile is brought in"
                return 0
                ;;
              *)
                _dm_escalate "$_t" merge "accepted, but merging orchestra/$_t into orchestra/run failed"
                return 0
                ;;
            esac
            ;;
          REJECT)
            _n=$(($(task_get "$_t" '.reject_rounds') + 1))
            # shellcheck disable=SC2016 # jq variables
            task_update "$_t" '.reject_rounds = $n' --argjson n "$_n"
            if [ "$_n" -ge "$_maxr" ]; then
              _dm_escalate "$_t" review "REJECTED $_n times (max_reject_rounds = $_maxr): the spec or the tests may be wrong"
              return 0
            fi
            _dm_feedback_reject "$_t"
            sm_transition "$_t" DRAFT "rejected ($_n/$_maxr), back to the agent"
            ;;
          ESCALATE)
            _dm_escalate "$_t" review "$(_dm_review_reason "$_t")"
            return 0
            ;;
          *)
            _dm_escalate "$_t" review "review failed: $(tail -n 3 "$(_dm_tdir "$_t")/review.err" | tr '\n' ' ')"
            return 0
            ;;
        esac
        ;;
      MERGED)
        worktree_remove "$_t"
        sm_transition "$_t" DONE "merged"
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  done
}

# daemon_integrate <task-id> — commit the task's work, bring in whatever was
# merged into orchestra/run since it branched (re-running VERIFY if anything
# came in), then merge it into orchestra/run. Returns 0 merged, 1 commit
# failed, 2 conflict, 3 VERIFY fails on the updated branch, 4 merge failed.
daemon_integrate() {
  _it=$1
  _iwt=$(_wt_dir "$_it")
  worktree_commit "$_it" "orchestra: $_it $(plan_task "$_it" '.desc')" || return 1
  bus_lock git
  _ihead=$(git -C "$_iwt" rev-parse HEAD)
  if ! worktree_update "$_it"; then
    bus_unlock git
    return 2
  fi
  if [ "$(git -C "$_iwt" rev-parse HEAD)" != "$_ihead" ]; then
    if ! ( runner_verify "$_it" "$_iwt" ) >/dev/null 2>&1; then
      bus_unlock git
      return 3
    fi
  fi
  if ! worktree_merge "$_it"; then
    bus_unlock git
    return 4
  fi
  if [ "$(config_get '.execution.integration // "end"')" = merge ]; then
    daemon_integration >/dev/null 2>&1 || true
  fi
  bus_unlock git
}

# daemon_integration — run stack.integration on orchestra/run (after
# stack.setup) and record .bus/integration.json. Returns 0 passed, 1 failed,
# 2 nothing to run. A failure is put in the inbox as integration.md.
daemon_integration() {
  _icmd=$(config_get '.stack.integration // empty')
  [ -n "$_icmd" ] || return 2
  _irun=$(_wt_dir _run)
  _ilog=$(bus_dir)/integration.log
  : >"$_ilog"
  _isetup=$(config_get '.stack.setup // empty')
  _ie=0
  if [ -n "$_isetup" ]; then
    ( cd "$_irun" && sh -c "$_isetup" ) >>"$_ilog" 2>&1 || _ie=$?
  fi
  if [ "$_ie" = 0 ]; then
    ( cd "$_irun" && sh -c "$_icmd" ) >>"$_ilog" 2>&1 && _ie=0 || _ie=$?
  fi
  jq -n --arg c "$_icmd" --argjson e "$_ie" --arg l "$_ilog" --arg at "$(now_iso)" \
    --arg rev "$(git -C "$_irun" rev-parse HEAD)" \
    '{passed: ($e == 0), cmd: $c, exit: $e, log: $l, commit: $rev, at: $at}' \
    >"$(bus_dir)/integration.json"
  bus_log "$(jq -c '{event: "integration"} + .' "$(bus_dir)/integration.json")"
  if [ "$_ie" = 0 ]; then
    rm -f "$(bus_dir)/escalations/integration.md"
    return 0
  fi
  mkdir -p "$(bus_dir)/escalations"
  {
    printf '# Integration build failed\n\n'
    printf -- '- Command: `%s` (exit %s)\n' "$_icmd" "$_ie"
    printf -- '- On: orchestra/run at %s\n' "$(git -C "$_irun" rev-parse --short HEAD)"
    printf -- '- Log: .bus/integration.log\n\n'
    printf 'Each task passed on its own; together they do not. Look at the log, fix the\n'
    printf 'design or the tasks involved (orchestra resolve ... amend-spec), then run\n'
    printf '`orchestra go` again.\n\n```\n'
    tail -n 40 "$_ilog"
    printf '```\n'
  } >"$(bus_dir)/escalations/integration.md"
  return 1
}

# _dm_trace_status — FR status from task states, in .bus/traceability.status.json.
_dm_trace_status() {
  _tr=$(project_root)/traceability.json
  [ -f "$_tr" ] || return 0
  _states=$(for _t in $(plan_get '.tasks[].id'); do
    jq -nc --arg t "$_t" --arg s "$(sm_state "$_t")" \
      --argjson v "$(jq '.passed' "$(bus_dir)/verify/$_t.json" 2>/dev/null || echo false)" \
      '{($t): {state: $s, verified: $v}}'
  done | jq -s 'add // {}')
  jq --argjson s "$_states" 'map_values({
      desc, tasks,
      status: (if (.tasks | length) > 0 and all(.tasks[]; $s[.].state == "DONE") then "accepted"
               elif (.tasks | length) > 0 and all(.tasks[]; $s[.].verified == true) then "implemented"
               else "planned" end)
    })' "$_tr" >"$(bus_dir)/traceability.status.json"
}

# _dm_summary — print the outcome; return 0 when every task is DONE (or the run
# was stopped), ORCHESTRA_EXIT_NEEDS_HUMAN otherwise.
_dm_summary() {
  _done=0
  _blocked=0
  _esc=0
  _wait=0
  for _t in $(plan_get '.tasks[].id'); do
    case $(sm_state "$_t") in
      DONE) _done=$((_done + 1)) ;;
      BLOCKED) _blocked=$((_blocked + 1)) ;;
      ESCALATED) _esc=$((_esc + 1)) ;;
      *) _wait=$((_wait + 1)) ;;
    esac
  done
  if _dm_stop_requested; then
    rm -f "$(bus_dir)/stop"
    printf '\nStopped: %s done, %s still to do. Run `orchestra go` to resume.\n' "$_done" "$((_blocked + _esc + _wait))"
    return 0
  fi
  printf '\nRun finished: %s done, %s blocked, %s escalated, %s waiting on them.\n' "$_done" "$_blocked" "$_esc" "$_wait"
  case ${1:-} in
    0) printf 'Integration build passed: `%s`.\n' "$(jq -r '.cmd' "$(bus_dir)/integration.json")" ;;
    1) printf 'Integration build FAILED: see .bus/escalations/integration.md.\n' ;;
  esac
  printf 'Merged work is on branch orchestra/run; review it and merge it into your branch when ready.\n'
  if [ $((_blocked + _esc + _wait)) -eq 0 ] && [ ! -f "$(bus_dir)/escalations/integration.md" ]; then
    return 0
  fi
  printf 'Needs a human:\n'
  for _e in "$(bus_dir)"/escalations/*.md; do
    if [ -f "$_e" ]; then printf '  %s\n' "${_e#"$(project_root)"/}"; fi
  done
  return "$ORCHESTRA_EXIT_NEEDS_HUMAN"
}

# daemon_running — an `orchestra go` run is active for this project.
daemon_running() {
  _rp=$(bus_dir)/run.pid
  [ -f "$_rp" ] && kill -0 "$(cat "$_rp")" 2>/dev/null
}

# daemon_loop — run up to execution.max_parallel tasks at once (one per agent)
# until none can make progress or a stop is requested; then run the
# integration build and summarise.
daemon_loop() {
  bus_init
  if daemon_running; then
    die "another orchestra go is already running for this project (pid $(cat "$(bus_dir)/run.pid"))"
  fi
  printf '%s\n' "$$" >"$(bus_dir)/run.pid"
  _RUN_PID_FILE=$(bus_dir)/run.pid
  trap '_rc=$?; rm -f "$_RUN_PID_FILE"
    case $_rc in 0 | 4 | 130) ;; *) printf "orchestra: phase 2 stopped unexpectedly (exit %s); state is kept in .bus/, run orchestra go to resume\n" "$_rc" >&2 ;; esac' EXIT
  trap 'exit 130' INT TERM
  rm -f "$(bus_dir)/stop"

  _max=$(config_get '.execution.max_parallel // (.agents | length)')
  [ "$_max" -ge 1 ] 2>/dev/null || _max=1
  _run_rev=$(git -C "$(_wt_dir _run)" rev-parse HEAD)
  printf '\nPhase 2: running the plan on branch orchestra/run, up to %s task(s) at once\n' "$_max"

  _nl='
'
  _running="" # one line per worker: <pid> <task> <agent> <state when launched>
  _stalled=""
  while :; do
    # Reap workers that finished (each leaves worker.done on exit).
    _keep=""
    while read -r _p _rt _ra _rs; do
      [ -n "$_p" ] || continue
      if [ ! -f "$(_dm_tdir "$_rt")/worker.done" ]; then
        _keep="$_keep$_p $_rt $_ra $_rs$_nl"
        continue
      fi
      wait "$_p" 2>/dev/null || true
      if ! _dm_stop_requested && [ "$(sm_state "$_rt")" = "$_rs" ]; then
        log_warn "task $_rt made no progress from $_rs; not retrying it in this run"
        _stalled="$_stalled$_rt$_nl"
      fi
    done <<EOF
$_running
EOF
    _running=$_keep

    if _dm_stop_requested; then
      [ -n "$_running" ] || break
      sleep 1
      continue
    fi

    # Launch workers while there is room, a runnable task and a free agent.
    while [ "$(printf '%s' "$_running" | grep -c .)" -lt "$_max" ]; do
      _ex=$(printf '%s' "$_running" | awk '{ print $2 }'; printf '%s' "$_stalled")
      _busy=$(printf '%s' "$_running" | awk '$3 != "-" { print $3 }')
      _pick=$(scheduler_next "$_ex" "$_busy")
      [ -n "$_pick" ] || break
      _pt=${_pick% *}
      _pa=${_pick#* }
      if [ "$_pa" != - ]; then
        task_update "$_pt" '.agent = $a' --arg a "$_pa"
      fi
      _ps=$(sm_state "$_pt")
      _mk=$(_dm_tdir "$_pt")/worker.done
      mkdir -p "$(_dm_tdir "$_pt")"
      rm -f "$_mk"
      ( trap ': >"$_mk"' EXIT; _dm_run_task "$_pt" ) &
      _running="$_running$! $_pt $_pa $_ps$_nl"
    done

    [ -n "$_running" ] || break
    sleep 1
  done

  _integ=""
  if ! _dm_stop_requested && [ "$(config_get '.execution.integration // "end"')" = end ] \
    && [ "$(git -C "$(_wt_dir _run)" rev-parse HEAD)" != "$_run_rev" ]; then
    printf '\nIntegration build on orchestra/run\n'
    if daemon_integration; then _integ=0; else _integ=$?; fi
  elif [ -f "$(bus_dir)/escalations/integration.md" ]; then
    _integ=1
  fi
  _dm_trace_status
  _dm_summary "$_integ"
}

# daemon_stop — `orchestra stop`: ask a running `orchestra go` to stop after
# its current step. State stays in .bus/; `orchestra go` resumes.
daemon_stop() {
  mkdir -p "$(bus_dir)"
  : >"$(bus_dir)/stop"
  printf 'Stop requested: the run stops after its current step. Resume with `orchestra go`.\n'
}
