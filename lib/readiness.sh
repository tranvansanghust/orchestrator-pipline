# shellcheck shell=sh
# DESIGN READINESS CHECK — blocks `orchestra go` until phase-1 artifacts are
# complete. Which checks are required depends on the profile
# (profiles/<name>.json); the rest are reported as SKIP.
#
#   coverage       every FR in the SRS is in traceability.json with >= 1 task;
#                  every task serves an FR
#   testability    every FR has tests and a test-plan section; done_when tests
#                  and traceability tests agree
#   rationale      every ADR-NNNN referenced in 02-architecture.md exists
#   api_spec       docs/04-api-spec.yaml is OpenAPI 3.x (full validation when
#                  redocly or swagger-cli is on PATH, light check otherwise)
#   data_model     05-data-model.md mentions every components.schemas entry
#   nfr            every NFR has a 'Metric | Target | How measured' row with a target
#   review_brief   docs/09-review-brief.md exists and is non-empty
#   plan_schema    plan.json (and traceability.json) match their schemas; spec
#                  files exist; deps are known and acyclic; each task's repos
#                  are configured and hold its scope and done_when tests
#
# Markdown is read through the conventions in templates/docs (ADR-0004).

_rd_docs() { printf '%s/docs\n' "$(project_root)"; }
_rd_trace() { printf '%s/traceability.json\n' "$(project_root)"; }

# _rd_gap <message> — report one gap; the current check fails.
_rd_gap() {
  printf '%s\n' "$*"
  _RD_BAD=1
}

# _rd_note <message> — informational line printed after the results.
_rd_note() { printf '%s\n' "$*" >>"$_RD_NOTES"; }

# _rd_in <item> <newline-separated list>
_rd_in() { printf '%s\n' "$2" | grep -qxF -- "$1"; }

# _rd_ids <id-regex> <file> — ids from '### <id>' or '### <id>: ...' headings.
_rd_ids() {
  [ -f "$2" ] || return 0
  grep -E "^### $1([: ]|\$)" "$2" | sed -E "s/^### ($1).*/\\1/" | LC_ALL=C sort -u
}

_rd_coverage() {
  _RD_BAD=0
  _srs=$(_rd_docs)/01-SRS.md
  _tr=$(_rd_trace)
  [ -f "$_srs" ] || { _rd_gap "missing docs/01-SRS.md"; return 1; }
  [ -f "$_tr" ] || { _rd_gap "missing traceability.json"; return 1; }
  _s=$(_rd_ids 'FR-[0-9]+' "$_srs")
  _t=$(jq -r 'keys[]' "$_tr" | LC_ALL=C sort -u)
  _p=$(plan_get '.tasks[].id')
  [ -n "$_s" ] || _rd_gap "no '### FR-<n>' headings in docs/01-SRS.md"
  for _fr in $_s; do
    if ! _rd_in "$_fr" "$_t"; then
      _rd_gap "$_fr is in the SRS but not in traceability.json"
      continue
    fi
    _tasks=$(jq -r --arg f "$_fr" '.[$f].tasks[]' "$_tr")
    [ -n "$_tasks" ] || _rd_gap "$_fr has no task"
    for _tk in $_tasks; do
      _rd_in "$_tk" "$_p" || _rd_gap "$_fr maps to $_tk, which is not in plan.json"
    done
  done
  for _fr in $_t; do
    _rd_in "$_fr" "$_s" || _rd_gap "$_fr is in traceability.json but not in the SRS"
  done
  for _tk in $_p; do
    jq -e --arg k "$_tk" 'any(.[]; .tasks | index($k))' "$_tr" >/dev/null \
      || _rd_gap "$_tk serves no FR in traceability.json"
  done
  return "$_RD_BAD"
}

_rd_testability() {
  _RD_BAD=0
  _tr=$(_rd_trace)
  _tp=$(_rd_docs)/06-test-plan.md
  [ -f "$_tr" ] || { _rd_gap "missing traceability.json"; return 1; }
  [ -f "$_tp" ] || { _rd_gap "missing docs/06-test-plan.md"; return 1; }
  _tph=$(_rd_ids 'FR-[0-9]+' "$_tp")
  for _fr in $(jq -r 'keys[]' "$_tr"); do
    [ -n "$(jq -r --arg f "$_fr" '.[$f].tests[]' "$_tr")" ] \
      || _rd_gap "$_fr has no test in traceability.json"
    _rd_in "$_fr" "$_tph" || _rd_gap "$_fr has no '### $_fr' section in docs/06-test-plan.md"
  done
  _pt=$(plan_get '[.tasks[].done_when.tests_pass[]] | unique[]')
  _tt=$(jq -r '[.[].tests[]] | unique[]' "$_tr")
  for _f in $_pt; do
    _rd_in "$_f" "$_tt" || _rd_gap "$_f (plan.json done_when) is not in traceability.json"
  done
  for _f in $_tt; do
    _rd_in "$_f" "$_pt" || _rd_gap "$_f (traceability.json) is not run by any task's done_when"
  done
  return "$_RD_BAD"
}

_rd_rationale() {
  _RD_BAD=0
  _arch=$(_rd_docs)/02-architecture.md
  [ -f "$_arch" ] || { _rd_gap "missing docs/02-architecture.md"; return 1; }
  _refs=$(grep -oE 'ADR-[0-9]{4}' "$_arch" | LC_ALL=C sort -u)
  [ -n "$_refs" ] || _rd_gap "docs/02-architecture.md references no ADR-NNNN"
  for _r in $_refs; do
    _n=${_r#ADR-}
    [ "$_n" != "0000" ] || continue
    set -- "$(_rd_docs)/03-adr/$_n"-*.md
    [ -e "$1" ] || _rd_gap "$_r is referenced but docs/03-adr/$_n-*.md does not exist"
  done
  return "$_RD_BAD"
}

_rd_api_spec() {
  _RD_BAD=0
  _spec=$(_rd_docs)/04-api-spec.yaml
  [ -f "$_spec" ] || { _rd_gap "missing docs/04-api-spec.yaml"; return 1; }
  if command -v redocly >/dev/null 2>&1; then
    redocly lint "$_spec" >/dev/null 2>&1 \
      || _rd_gap "redocly lint failed on docs/04-api-spec.yaml (run it for details)"
  elif command -v swagger-cli >/dev/null 2>&1; then
    swagger-cli validate "$_spec" >/dev/null 2>&1 \
      || _rd_gap "swagger-cli validate failed on docs/04-api-spec.yaml (run it for details)"
  else
    grep -Eq "^openapi:[[:space:]]*[\"']?3\\." "$_spec" \
      || _rd_gap "docs/04-api-spec.yaml has no 'openapi: 3.x'"
    grep -Eq '^paths:' "$_spec" \
      || _rd_gap "docs/04-api-spec.yaml has no top-level 'paths:'"
    _rd_note "api_spec: light check only (no redocly or swagger-cli on PATH); install one for full OpenAPI validation"
  fi
  return "$_RD_BAD"
}

_rd_data_model() {
  _RD_BAD=0
  _dm=$(_rd_docs)/05-data-model.md
  _spec=$(_rd_docs)/04-api-spec.yaml
  [ -f "$_dm" ] || { _rd_gap "missing docs/05-data-model.md"; return 1; }
  [ -f "$_spec" ] || { _rd_gap "missing docs/04-api-spec.yaml"; return 1; }
  _names=$(awk '
    /^  schemas:/ { f = 1; next }
    f && /^[^ ]/ { f = 0 }
    f && /^  [^ ]/ { f = 0 }
    f && /^    [A-Za-z0-9_]+:/ { sub(/^    /, ""); sub(/:.*/, ""); print }
  ' "$_spec")
  for _n in $_names; do
    grep -qw -- "$_n" "$_dm" \
      || _rd_gap "schema $_n (components.schemas) is not mentioned in docs/05-data-model.md"
  done
  return "$_RD_BAD"
}

_rd_nfr() {
  _RD_BAD=0
  _nfr=$(_rd_docs)/07-nfr.md
  [ -f "$_nfr" ] || { _rd_gap "missing docs/07-nfr.md"; return 1; }
  _ids=$(_rd_ids 'NFR-[0-9]+' "$_nfr")
  [ -n "$_ids" ] || _rd_gap "no '### NFR-<n>' headings in docs/07-nfr.md"
  for _id in $_ids; do
    # Rows 1-2 of the table are header + separator; any later row with a
    # non-empty Target cell (column 2) counts as measurable.
    awk -v id="$_id" '
      $0 ~ ("^### " id "([: ]|$)") { f = 1; next }
      f && /^### / { f = 0 }
      f && /^\|/ {
        n++
        if (n >= 3) { split($0, c, "|"); t = c[3]; gsub(/^[ \t]+|[ \t]+$/, "", t); if (t != "") ok = 1 }
      }
      END { exit ok ? 0 : 1 }
    ' "$_nfr" || _rd_gap "$_id has no measurable target (needs a 'Metric | Target | How measured' row with a Target)"
  done
  return "$_RD_BAD"
}

_rd_review_brief() {
  _RD_BAD=0
  [ -s "$(_rd_docs)/09-review-brief.md" ] || _rd_gap "missing or empty docs/09-review-brief.md"
  return "$_RD_BAD"
}

# _rd_cycles <task-ids> — repeatedly remove tasks whose deps are all removed;
# whatever cannot be removed sits on a cycle.
_rd_cycles() {
  _pending=$1
  while [ -n "$_pending" ]; do
    _next=""
    _moved=0
    for _id in $_pending; do
      _blocked=0
      for _d in $(plan_task "$_id" '.deps[]?'); do
        if _rd_in "$_d" "$_pending"; then
          _blocked=1
          break
        fi
      done
      if [ "$_blocked" = 1 ]; then
        _next="$_next
$_id"
      else
        _moved=1
      fi
    done
    _pending=$(printf '%s\n' "$_next" | sed '/^$/d')
    if [ "$_moved" = 0 ]; then
      _rd_gap "dependency cycle among: $(printf '%s\n' "$_pending" | tr '\n' ' ')"
      return 0
    fi
  done
}

# _rd_task_repos <task-id> — the task's repos exist in the config, and its
# scope globs and done_when tests fall inside them (ADR-0013).
_rd_task_repos() {
  _trs=$(task_repos "$1")
  _known=$(repo_names)
  for _r in $_trs; do
    _rd_in "$_r" "$_known" || _rd_gap "$1: repo $_r is not configured (repos in orchestra.config.json)"
  done
  # The loop runs in a subshell, so gaps come back as text.
  _out=$(plan_task "$1" '(.scope // [])[], .done_when.tests_pass[]' | while IFS= read -r _tp; do
    _own=$(repo_of "$_tp")
    _rd_in "$_own" "$_trs" \
      || printf '%s: %s is in repo %s, which is not in its repos (%s)\n' \
        "$1" "$_tp" "$_own" "$(printf '%s\n' "$_trs" | paste -sd, -)"
  done)
  [ -z "$_out" ] || _rd_gap "$_out"
}

_rd_plan_schema() {
  _RD_BAD=0
  _root=$(project_root)
  [ -f "$_root/plan.json" ] || { _rd_gap "missing plan.json"; return 1; }
  if ! command -v check-jsonschema >/dev/null 2>&1; then
    _rd_gap "check-jsonschema is not installed (needed to validate plan.json)"
    return 1
  fi
  check-jsonschema --schemafile "$ORCHESTRA_HOME/schemas/plan.schema.json" "$_root/plan.json" >/dev/null 2>&1 \
    || { _rd_gap "plan.json does not match schemas/plan.schema.json (run check-jsonschema for details)"; return 1; }
  if [ -f "$_root/traceability.json" ]; then
    check-jsonschema --schemafile "$ORCHESTRA_HOME/schemas/traceability.schema.json" "$_root/traceability.json" >/dev/null 2>&1 \
      || _rd_gap "traceability.json does not match schemas/traceability.schema.json"
  fi
  _ids=$(plan_get '.tasks[].id')
  _dup=$(printf '%s\n' "$_ids" | LC_ALL=C sort | uniq -d | tr '\n' ' ')
  [ -z "$_dup" ] || _rd_gap "duplicate task ids: $_dup"
  for _id in $_ids; do
    _sf=$(plan_task "$_id" '.spec_file')
    [ "$_sf" = "docs/specs/$_id.md" ] || _rd_gap "$_id: spec_file is $_sf, expected docs/specs/$_id.md"
    [ -f "$_root/$_sf" ] || _rd_gap "$_id: $_sf does not exist"
    for _d in $(plan_task "$_id" '.deps[]?'); do
      _rd_in "$_d" "$_ids" || _rd_gap "$_id depends on unknown task $_d"
    done
    _rd_task_repos "$_id"
  done
  _rd_cycles "$_ids"
  return "$_RD_BAD"
}

# readiness_check <profile> — run the profile's checks, print every gap,
# return non-zero if any required check fails.
readiness_check() {
  _profile=${1:-}
  [ -n "$_profile" ] || die "readiness_check: profile required"
  _pf=$ORCHESTRA_HOME/profiles/$_profile.json
  [ -f "$_pf" ] || die "unknown profile: $_profile (expected lite, standard or strict)"
  _RD_NOTES=$(mktemp)
  _failed=0
  printf 'Design readiness check (profile: %s)\n' "$_profile"
  for _c in coverage testability rationale api_spec data_model nfr review_brief plan_schema; do
    if [ "$(jq -r --arg c "$_c" '.readiness[$c] // false' "$_pf")" != "true" ]; then
      printf '  SKIP  %s\n' "$_c"
      continue
    fi
    if _out=$("_rd_$_c" 2>&1); then
      printf '  PASS  %s\n' "$_c"
    else
      printf '  FAIL  %s\n' "$_c"
      printf '%s\n' "$_out" | sed -e '/^$/d' -e 's/^/          - /'
      _failed=1
    fi
  done
  if [ -s "$_RD_NOTES" ]; then
    sed 's/^/  NOTE  /' "$_RD_NOTES"
  fi
  rm -f "$_RD_NOTES"
  [ "$_failed" = 0 ]
}
