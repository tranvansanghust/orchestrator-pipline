# shellcheck shell=sh
# Path back to the human (ADR-0011). "Not sure" always means STOP, never GO; a
# task that needs a human is never auto-accepted, and only blocks itself and
# its dependents while the rest of the plan keeps running.
#
# The rules that decide to escalate live where the evidence is: review hard
# rules in lib/review.sh, retry limits in lib/daemon.sh. This file records the
# result and resolves it:
#   inbox    .bus/escalations/<id>.md, plus a tmux message when the cockpit runs
#   handoff  `orchestra resolve <id>` opens Claude with the escalation loaded
#   resolve  accept | reject "<msg>" | retry ["<msg>"] | amend-spec "<msg>"

# escalation_open <task-id> <kind> <reason> — write .bus/escalations/<id>.md
# for a task that is BLOCKED or ESCALATED, and log it.
escalation_open() {
  _et=$1
  _ek=$2
  _er=$3
  _edir=$(bus_dir)/escalations
  mkdir -p "$_edir"
  {
    printf '# %s: %s\n\n' "$_et" "$(sm_state "$_et")"
    printf -- '- Task: %s\n' "$(plan_task "$_et" '.desc')"
    printf -- '- Kind: %s\n' "$_ek"
    printf -- '- Raised: %s\n\n' "$(now_iso)"
    printf '## Why\n\n%s\n\n' "$_er"
    printf '## Where to look\n\n'
    printf -- '- worktree: .worktrees/%s (branch orchestra/%s)\n' "$_et" "$_et"
    if [ "$(config_get '.repos // {} | length')" -gt 0 ]; then
      printf -- '- repos it may change: %s; each has branch orchestra/%s, checked out at its own path inside the worktree\n' \
        "$(task_repos "$_et" | paste -sd, - | sed 's/,/, /g')" "$_et"
    fi
    printf -- '- agent prompts and feedback: .bus/tasks/%s/\n' "$_et"
    printf -- '- verify report: .bus/verify/%s.json\n' "$_et"
    printf -- '- review rounds: .bus/review/%s/\n\n' "$_et"
    printf '## Next step\n\n'
    printf 'The task and the tasks that depend on it wait; the rest of the plan keeps going.\n'
    printf 'Run `orchestra resolve %s` to look at it with Claude, or resolve directly:\n\n' "$_et"
    printf '    orchestra resolve %s accept                 # merge the change as it is\n' "$_et"
    printf '    orchestra resolve %s reject "<what to fix>" # back to the agent\n' "$_et"
    printf '    orchestra resolve %s retry                  # the blocking problem is fixed\n' "$_et"
    printf '    orchestra resolve %s amend-spec "<change>"  # after editing the design docs\n' "$_et"
  } >"$_edir/$_et.md"
  bus_log "$(jq -nc --arg t "$_et" --arg k "$_ek" --arg r "$_er" \
    '{event: "escalation", task: $t, kind: $k, reason: $r}')"
  if command -v tmux_notify >/dev/null 2>&1; then
    tmux_notify "orchestra: $_et needs a human ($_ek) - orchestra resolve $_et"
  fi
}

# _res_feedback <task-id> <title> <message> — note for the agent's next prompt.
_res_feedback() {
  mkdir -p "$(bus_dir)/tasks/$1"
  {
    printf '## %s\n\n' "$2"
    if [ -n "$3" ]; then printf '%s\n' "$3"; fi
  } >"$(bus_dir)/tasks/$1/feedback.md"
}

# _res_close <task-id> <action> <message> — archive the inbox entry and log.
_res_close() {
  _edir=$(bus_dir)/escalations
  if [ -f "$_edir/$1.md" ]; then
    mkdir -p "$_edir/resolved"
    mv "$_edir/$1.md" "$_edir/resolved/$1-$(date -u +%Y%m%dT%H%M%SZ).md"
  fi
  bus_log "$(jq -nc --arg t "$1" --arg a "$2" --arg m "$3" \
    '{event: "resolve", task: $t, action: $a, message: $m}')"
}

# _res_require_idle — refuse while an `orchestra go` run is active.
_res_require_idle() {
  if daemon_running; then
    die "an orchestra go run is active (pid $(cat "$(bus_dir)/run.pid")); stop it first with orchestra stop"
  fi
}

# _res_handoff <task-id> — open Claude with the escalation loaded (TUI handoff).
_res_handoff() {
  _ht=$1
  _hp=$(bus_dir)/tasks/$_ht/handoff.md
  mkdir -p "$(dirname "$_hp")"
  {
    printf 'Task %s of this orchestra project stopped and needs a decision from me.\n' "$_ht"
    printf 'Help me resolve it, following the /resolve procedure:\n\n'
    sed -n '/^---$/,/^---$/!p' "$ORCHESTRA_HOME/commands/resolve.md" | sed 's/\$ARGUMENTS/'"$_ht"'/g'
    printf '\n\nThe inbox entry:\n\n'
    if [ -f "$(bus_dir)/escalations/$_ht.md" ]; then cat "$(bus_dir)/escalations/$_ht.md"; fi
  } >"$_hp"
  _hc=$(brain_cmd planner)
  if command -v tmux_handoff >/dev/null 2>&1 && tmux_handoff "resolve-$_ht" "$_hc" "$_hp"; then
    return 0
  fi
  eval "set -- $_hc"
  cd "$(project_root)" || die "cannot enter $(project_root)"
  exec "$@" "$(cat "$_hp")"
}

# _res_accept <task-id> — merge an escalated change as it is.
_res_accept() {
  [ "$(sm_state "$1")" = ESCALATED ] \
    || die "$1 is BLOCKED (VERIFY or setup failed): use retry or reject, not accept"
  [ "$(jq -r '.passed' "$(bus_dir)/verify/$1.json" 2>/dev/null)" = true ] \
    || die "$1 has no passing VERIFY report; it cannot be accepted"
  [ -d "$(_wt_dir "$1")" ] || die "$1 has no worktree (.worktrees/$1)"
  if daemon_integrate "$1"; then :; else
    case $? in
      1) die "could not commit the work in .worktrees/$1" ;;
      2) die "orchestra/$1 conflicts with work merged into orchestra/run since; resolve the conflict in .worktrees/$1 (git merge orchestra/run, in each repo of the task), commit, and accept again" ;;
      3) die "VERIFY fails once orchestra/run is merged into orchestra/$1; use reject to send it back to the agent" ;;
      *) die "merging orchestra/$1 into orchestra/run failed" ;;
    esac
  fi
  sm_transition "$1" MERGED "accepted by a human"
  worktree_remove "$1"
  sm_transition "$1" DONE "merged"
}

# _res_back <task-id> <title> <message> — send the task back to the agent with
# a fresh retry budget (a human looked at it).
_res_back() {
  _res_feedback "$1" "$2" "$3"
  task_update "$1" '.verify_rounds = 0 | .reject_rounds = 0'
  sm_transition "$1" DRAFT "$2"
}

# _res_amend <task-id> <message> — the design was wrong and has been edited:
# re-check and re-freeze it, then restart the task from scratch.
_res_amend() {
  _at=$1
  _drift=$(_go_drift)
  [ -n "$_drift" ] || die "no design change since the freeze; edit docs/ (SRS, test plan, spec) first, then amend-spec"
  printf 'Design changes:\n%s\n\n' "$(printf '%s\n' "$_drift" | sed 's/^/  /')"
  _prof=$(jq -r '.profile' "$(bus_dir)/frozen.json")
  readiness_check "$_prof" || die "the amended design fails the readiness check; fix the gaps above"
  _go_freeze "$_prof"
  worktree_run_init
  worktree_remove "$_at"
  worktree_drop_branches "$_at"
  if [ -d "$(bus_dir)/review/$_at" ]; then
    mv "$(bus_dir)/review/$_at" "$(bus_dir)/review/$_at.superseded-$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  rm -f "$(bus_dir)/verify/$_at.json"
  _res_feedback "$_at" "The specification of this task was amended" \
    "$2

You start again from scratch on the amended design; re-read the spec below."
  task_update "$_at" 'del(.base, .bases, .branch, .worktree, .agent_rc) | .verify_rounds = 0 | .reject_rounds = 0'
  sm_transition "$_at" DRAFT "spec amended"
}

# escalation_resolve <task-id> [accept | reject <msg> | retry [msg] | amend-spec <msg>]
escalation_resolve() {
  [ $# -ge 1 ] || {
    printf 'usage: orchestra resolve <task> [accept | reject "<msg>" | retry ["<msg>"] | amend-spec "<msg>"]\n' >&2
    exit "$ORCHESTRA_EXIT_USAGE"
  }
  _t=$1
  _act=${2:-}
  _msg=${3:-}
  [ -n "$(plan_task "$_t" '.id // empty')" ] || die "unknown task: $_t"
  _st=$(sm_state "$_t")
  case $_st in
    BLOCKED | ESCALATED) ;;
    *) die "$_t is $_st; only BLOCKED or ESCALATED tasks can be resolved" ;;
  esac
  case $_act in
    "")
      _res_handoff "$_t"
      return 0
      ;;
    accept)
      _res_require_idle
      _res_accept "$_t"
      ;;
    reject)
      [ -n "$_msg" ] || die "reject needs a message for the agent: orchestra resolve $_t reject \"<what to fix>\""
      _res_back "$_t" "A human reviewer sent this task back" "$_msg"
      ;;
    retry)
      _res_back "$_t" "Retrying after the blocking problem was fixed" "$_msg"
      ;;
    amend-spec)
      [ -n "$_msg" ] || die "amend-spec needs a message describing the change"
      _res_require_idle
      _res_amend "$_t" "$_msg"
      ;;
    *)
      printf 'orchestra resolve: unknown action: %s\n' "$_act" >&2
      exit "$ORCHESTRA_EXIT_USAGE"
      ;;
  esac
  _res_close "$_t" "$_act" "$_msg"
  printf 'Resolved %s: %s (now %s).\n' "$_t" "$_act" "$(sm_state "$_t")"
  if daemon_running; then
    printf 'The running orchestra go picks it up.\n'
  elif [ "$(sm_state "$_t")" != DONE ]; then
    printf 'Run `orchestra go` to continue.\n'
  fi
}
