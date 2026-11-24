# shellcheck shell=sh
# REVIEW layer (ADR-0005, ADR-0008). Runs only after VERIFY is green.
#
#   1. build a context pack from artifacts (the reviewer is stateless)
#   2. reviewer: claude -p, no tools, structured output -> verdict.json
#   3. confirmer (ACCEPT only): checks the verdict against its evidence
#   4. hard rules: low confidence, high/critical concern, always_human area,
#      diff outside scope, reviewer asks for a human -> ESCALATE
#   5. decision.json: the effective verdict the daemon acts on
#
# Pack sections:
#   spec, verify, diff, tests, previous   never dropped
#   brief, architecture, contracts, conventions
#                                         optional; when over max_pack_bytes
#                                         dropped in the order of _RV_OPTIONAL
#                                         (conventions first, brief last)
# The rubric is part of the reviewer's system prompt and is never dropped.
# Agent-written content (diff, tests) is wrapped in <untrusted-data> blocks
# tagged with a per-round random id.
#
# Each round lives in .bus/review/<task>/round-<n>/.

_RV_OPTIONAL="conventions contracts architecture brief"

# _rv_doc <name> — docs/<name> from the project if present, else the default.
_rv_doc() {
  if [ -f "$(project_root)/docs/$1" ]; then
    printf '%s\n' "$(project_root)/docs/$1"
  else
    printf '%s\n' "$ORCHESTRA_HOME/templates/review/$1"
  fi
}

_rv_nonce() { od -An -N8 -tx1 /dev/urandom | tr -d ' \n'; }

# _rv_untrusted <source> <file>
_rv_untrusted() {
  printf '<untrusted-data id="%s" source="%s">\n' "$_RV_NONCE" "$1"
  cat "$2"
  printf '\n</untrusted-data id="%s">\n' "$_RV_NONCE"
}

# _rv_section <dir> <name> <title> <file> [lang] — write one pack section from
# a file (skipped when the file does not exist).
_rv_section() {
  [ -f "$4" ] || return 0
  {
    printf '## %s\n\n' "$3"
    if [ -n "${5:-}" ]; then
      printf '```%s\n' "$5"
      cat "$4"
      printf '\n```\n'
    else
      cat "$4"
    fi
    printf '\n'
  } >"$1/$2.md"
}

# _rv_size <file> — size in bytes.
_rv_size() { wc -c <"$1" | tr -d ' '; }

# review_build_pack <task-id> <worktree> <round-dir> <round> — write
# <round-dir>/pack.md. Returns 2 when the pack cannot fit max_pack_bytes even
# with every optional section dropped.
review_build_pack() {
  _task=$1
  _wt=$2
  _dir=$3
  _round=$4
  _docs=$(project_root)/docs
  _sec=$_dir/sections
  mkdir -p "$_sec"
  : >"$_dir/dropped.txt"

  # spec: task metadata + its spec file
  {
    printf '## Task %s\n\n' "$_task"
    plan_task "$_task" '{id, desc, areas, scope, done_when}' | sed 's/^/    /'
    printf '\n'
    if [ -f "$(project_root)/$(plan_task "$_task" '.spec_file')" ]; then
      printf '### Spec\n\n'
      cat "$(project_root)/$(plan_task "$_task" '.spec_file')"
      printf '\n'
    fi
  } >"$_sec/spec.md"

  _rv_section "$_sec" verify "Verify report (machine output, trusted)" "$(bus_dir)/verify/$_task.json" json

  {
    printf '## Diff since the task base\n\n'
    _rv_untrusted diff "$_dir/diff.patch"
  } >"$_sec/diff.md"

  {
    printf '## Tests (done_when.tests_pass, as found in the worktree)\n\n'
    plan_task "$_task" '.done_when.tests_pass[]?' | while IFS= read -r _tf; do
      if [ -f "$_wt/$_tf" ]; then
        printf '### %s\n\n' "$_tf"
        _rv_untrusted "test:$_tf" "$_wt/$_tf"
      else
        printf '### %s\n\nNot found in the worktree.\n\n' "$_tf"
      fi
    done
  } >"$_sec/tests.md"

  if [ "$_round" -gt 1 ]; then
    _prev=$(dirname "$_dir")/round-$((_round - 1))
    if [ -f "$_prev/verdict.json" ]; then
      {
        printf '## Previous review round (%s)\n\n' "$((_round - 1))"
        printf 'The agent revised the change after this verdict. Check that every requested fix was made.\n\n'
        printf '```json\n'
        jq '{verdict, summary, concerns, fixes_requested}' "$_prev/verdict.json"
        printf '```\n\n'
      } >"$_sec/previous.md"
    fi
  fi

  _rv_section "$_sec" contracts "Contracts (docs/04-api-spec.yaml)" "$_docs/04-api-spec.yaml" yaml
  _rv_section "$_sec" brief "Review brief" "$_docs/09-review-brief.md"
  _rv_section "$_sec" architecture "Architecture" "$_docs/02-architecture.md"
  _rv_section "$_sec" conventions "Conventions" "$(_rv_doc conventions.md)"

  _max=$(config_get '.review.max_pack_bytes // 400000')
  _total=0
  for _s in "$_sec"/*.md; do
    _total=$((_total + $(_rv_size "$_s")))
  done
  for _s in $_RV_OPTIONAL; do
    [ "$_total" -gt "$_max" ] || break
    if [ -f "$_sec/$_s.md" ]; then
      _total=$((_total - $(_rv_size "$_sec/$_s.md")))
      rm -f "$_sec/$_s.md"
      printf '%s\n' "$_s" >>"$_dir/dropped.txt"
    fi
  done

  {
    printf '# Review context pack: task %s, round %s\n\n' "$_task" "$_round"
    if [ -s "$_dir/dropped.txt" ]; then
      printf 'Dropped to fit the size budget: %s\n\n' "$(tr '\n' ' ' <"$_dir/dropped.txt")"
    fi
    for _s in spec verify diff tests previous contracts brief architecture conventions; do
      [ -f "$_sec/$_s.md" ] && cat "$_sec/$_s.md"
    done
  } >"$_dir/pack.md"

  [ "$_total" -le "$_max" ] || return 2
  return 0
}

# _rv_call <role> <system-file> <prompt-file> <schema-name> <raw-out> — one
# headless claude call with structured output. Returns non-zero on CLI failure.
_rv_call() {
  _cr=$1
  _csys=$2
  _cprompt=$3
  _cschema=$4
  _craw=$5
  _ccmd=$(brain_cmd "$_cr")
  _cmodel=$(brain_model "$_cr")
  _cbudget=$(config_get '.review.max_budget_usd // 1')
  # Conditional keywords are enforced by our own validation afterwards.
  _cjs=$(jq -c 'del(.["$schema"], .["$id"], .allOf)' "$ORCHESTRA_HOME/schemas/$_cschema.schema.json")
  eval "set -- $_ccmd"
  set -- "$@" --output-format json --tools "" --json-schema "$_cjs" \
    --max-budget-usd "$_cbudget" --system-prompt "$(cat "$_csys")"
  if [ -n "$_cmodel" ]; then
    set -- "$@" --model "$_cmodel"
  fi
  "$@" <"$_cprompt" >"$_craw" 2>"$_craw.err"
}

# _rv_extract <raw> <out> <schema-name> <task-id> — pull structured_output out
# of the envelope and validate it. Prints the problem and returns 1 if invalid.
_rv_extract() {
  if ! jq -e '.is_error == false' "$1" >/dev/null 2>&1; then
    printf 'the CLI reported an error or returned no JSON envelope (subtype: %s)\n' \
      "$(jq -r '.subtype // "none"' "$1" 2>/dev/null || echo none)"
    return 1
  fi
  if ! jq -e '.structured_output // (.result | fromjson?) | objects' "$1" >"$2" 2>/dev/null; then
    printf 'the reply contained no JSON object\n'
    return 1
  fi
  if ! _xerr=$(check-jsonschema --schemafile "$ORCHESTRA_HOME/schemas/$3.schema.json" "$2" 2>&1); then
    printf 'the JSON does not match schemas/%s.schema.json: %s\n' "$3" "$(printf '%s' "$_xerr" | tail -3 | tr '\n' ' ')"
    return 1
  fi
  if ! jq -e --arg t "$4" '.task == $t' "$2" >/dev/null; then
    printf 'task is %s, expected %s\n' "$(jq -r '.task' "$2")" "$4"
    return 1
  fi
}

# _rv_cost <raw> — the call's cost, 0 when unknown.
_rv_cost() { jq -r '.total_cost_usd // 0' "$1" 2>/dev/null || echo 0; }

# _rv_ask <role> <system> <prompt> <schema> <dir> <name> <task> — call, extract,
# retry once with the error appended. Leaves <dir>/<name>.json on success.
_rv_ask() {
  _ar=$1
  _asys=$2
  _aprompt=$3
  _aschema=$4
  _adir=$5
  _aname=$6
  _atask=$7
  for _try in 1 2; do
    _rv_call "$_ar" "$_asys" "$_aprompt" "$_aschema" "$_adir/$_aname-raw-$_try.json" || true
    _RV_COST=$(awk -v a="$_RV_COST" -v b="$(_rv_cost "$_adir/$_aname-raw-$_try.json")" 'BEGIN { print a + b }')
    if _aerr=$(_rv_extract "$_adir/$_aname-raw-$_try.json" "$_adir/$_aname.json" "$_aschema" "$_atask"); then
      return 0
    fi
    printf '%s\n' "$_aerr" >"$_adir/$_aname-error-$_try.txt"
    {
      cat "$_aprompt"
      printf '\n\n---\nYour previous reply was rejected: %s\nReply again with a single JSON object that matches the schema.\n' "$_aerr"
    } >"$_adir/$_aname-prompt-retry.md"
    _aprompt=$_adir/$_aname-prompt-retry.md
  done
  rm -f "$_adir/$_aname.json"
  return 1
}

# _rv_rules <task-id> <verdict-file> <changed-files-file> — print one line per
# hard escalation rule that fires.
_rv_rules() {
  _rt=$1
  _rvf=$2
  _rv=$(jq -r '.verdict' "$_rvf")
  [ "$_rv" != ESCALATE ] || return 0
  _thr=$(config_get '.escalation.confidence_threshold // 0.75')
  _conf=$(jq -r '.confidence' "$_rvf")
  if awk -v c="$_conf" -v t="$_thr" 'BEGIN { exit !(c < t) }'; then
    printf 'reviewer confidence %s is below the threshold %s\n' "$_conf" "$_thr"
  fi
  _hi=$(jq -r '[.concerns[]? | select(.severity == "high" or .severity == "critical")] | length' "$_rvf")
  [ "$_hi" = 0 ] || printf 'reviewer raised %s high/critical concern(s)\n' "$_hi"
  if [ "$(jq -r '.needs_human // false' "$_rvf")" = true ]; then
    printf 'reviewer asked for a human: %s\n' "$(jq -r '.question_for_human // ""' "$_rvf")"
  fi
  if [ "$_rv" = ACCEPT ]; then
    _human=$(config_get '.escalation.always_human[]?')
    for _a in $(plan_task "$_rt" '.areas[]?'); do
      if printf '%s\n' "$_human" | grep -qxF -- "$_a"; then
        printf 'task area "%s" is always_human\n' "$_a"
      fi
    done
  fi
  _scope=$(plan_task "$_rt" '.scope[]?')
  if [ -n "$_scope" ]; then
    _allowed=$(printf '%s\n%s\n' "$_scope" "$(plan_task "$_rt" '.done_when.tests_pass[]?')")
    set -f # scope globs are case patterns, not paths to expand
    while IFS= read -r _f; do
      [ -n "$_f" ] || continue
      _ok=0
      for _g in $_allowed; do
        # shellcheck disable=SC2254
        case $_f in
          $_g) _ok=1; break ;;
        esac
      done
      [ "$_ok" = 1 ] || printf 'changed file %s is outside the task scope\n' "$_f"
    done <"$3"
    set +f
  fi
}

# _rv_synthetic <task-id> <out> <reason> — an ESCALATE verdict made by the engine.
_rv_synthetic() {
  jq -n --arg t "$1" --arg r "$3" '{
    task: $t, verdict: "ESCALATE", confidence: 0,
    summary: ("No usable reviewer verdict: " + $r),
    evidence: [{claim: $r, source: "reviewer_inference"}],
    needs_human: true,
    question_for_human: ("Review " + $t + " manually: " + $r)
  }' >"$2"
}

# review_run <task-id> <worktree> — run one review round; print the effective
# verdict (ACCEPT | REJECT | ESCALATE).
review_run() {
  _task=$1
  _wt=$2
  _vr=$(bus_dir)/verify/$_task.json
  [ "$(jq -r '.passed' "$_vr" 2>/dev/null)" = true ] \
    || die "review $_task: VERIFY is not green (.bus/verify/$_task.json)"

  _base=$(bus_dir)/review/$_task
  mkdir -p "$_base"
  _round=1
  while [ -d "$_base/round-$_round" ]; do
    _round=$((_round + 1))
  done
  _dir=$_base/round-$_round
  mkdir -p "$_dir"
  _RV_NONCE=$(_rv_nonce)
  _RV_COST=0
  _synthetic=false
  : >"$_dir/reasons.txt"

  worktree_diff "$_task" "$_wt" >"$_dir/diff.patch"
  worktree_changed_files "$_task" "$_wt" >"$_dir/changed.txt"

  if review_build_pack "$_task" "$_wt" "$_dir" "$_round"; then
    { cat "$ORCHESTRA_HOME/templates/review/reviewer-system.md"; printf '\n\n'; cat "$(_rv_doc rubric.md)"; } \
      >"$_dir/reviewer-system.md"
    if ! _rv_ask reviewer "$_dir/reviewer-system.md" "$_dir/pack.md" verdict "$_dir" verdict "$_task"; then
      _rv_synthetic "$_task" "$_dir/verdict.json" "reviewer output was invalid twice ($(cat "$_dir/verdict-error-2.txt"))"
      _synthetic=true
    fi
  else
    _rv_synthetic "$_task" "$_dir/verdict.json" \
      "the context pack exceeds review.max_pack_bytes even with optional sections dropped; the diff is too large for one review"
    _synthetic=true
  fi

  _reviewer=$(jq -r '.verdict' "$_dir/verdict.json")
  _effective=$_reviewer
  _upheld=null

  if [ "$_reviewer" = ACCEPT ]; then
    {
      printf '# Confirm the verdict for task %s\n\n' "$_task"
      printf '## Task\n\n'
      plan_task "$_task" '{id, desc, areas, done_when}' | sed 's/^/    /'
      printf '\n## Verify report (machine output, trusted)\n\n```json\n'
      cat "$_vr"
      # Backticks are a markdown fence, not a command substitution.
      # shellcheck disable=SC2016
      printf '\n```\n\n## Reviewer verdict under review\n\n```json\n'
      cat "$_dir/verdict.json"
      printf '\n```\n'
    } >"$_dir/confirmer-prompt.md"
    if _rv_ask confirmer "$ORCHESTRA_HOME/templates/review/confirmer-system.md" \
      "$_dir/confirmer-prompt.md" confirmation "$_dir" confirmation "$_task"; then
      _upheld=$(jq -r '.upheld' "$_dir/confirmation.json")
      _supported=$(jq -r '.supported' "$_dir/confirmation.json")
      if [ "$_upheld" != true ]; then
        # Never upward: an ACCEPT that is not upheld cannot stay ACCEPT.
        if [ "$_supported" = ACCEPT ]; then _effective=ESCALATE; else _effective=$_supported; fi
        printf 'confirmer did not uphold ACCEPT: %s\n' "$(jq -r '.reason' "$_dir/confirmation.json")" >>"$_dir/reasons.txt"
      fi
    else
      _upheld=false
      _effective=ESCALATE
      printf 'confirmer output was invalid twice\n' >>"$_dir/reasons.txt"
    fi
  fi

  if [ "$_effective" != ESCALATE ]; then
    jq --arg v "$_effective" '.verdict = $v' "$_dir/verdict.json" >"$_dir/effective.json"
    _rv_rules "$_task" "$_dir/effective.json" "$_dir/changed.txt" >"$_dir/rules.txt"
    if [ -s "$_dir/rules.txt" ]; then
      cat "$_dir/rules.txt" >>"$_dir/reasons.txt"
      _effective=ESCALATE
    fi
  fi

  jq -n \
    --arg t "$_task" --argjson r "$_round" --arg v "$_effective" --arg rv "$_reviewer" \
    --argjson up "$_upheld" --argjson syn "$_synthetic" --argjson cost "$_RV_COST" \
    --arg at "$(now_iso)" \
    --rawfile reasons "$_dir/reasons.txt" --rawfile dropped "$_dir/dropped.txt" '{
      task: $t, round: $r, verdict: $v, reviewer_verdict: $rv, upheld: $up,
      reasons: ($reasons | split("\n") | map(select(length > 0))),
      dropped_sections: ($dropped | split("\n") | map(select(length > 0))),
      synthetic_verdict: $syn, cost_usd: $cost, decided_at: $at
    }' >"$_dir/decision.json"

  printf '%s\n' "$_effective"
}
