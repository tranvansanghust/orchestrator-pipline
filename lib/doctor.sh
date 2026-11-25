# shellcheck shell=sh
# `orchestra doctor` — check the machine and, inside a project, its config and
# agents. Exits non-zero when something required is missing.

_doc_ok() { printf '  ok    %s\n' "$*"; }
_doc_warn() { printf '  warn  %s\n' "$*"; }
_doc_fail() {
  printf '  FAIL  %s\n' "$*"
  _DOC_FAILED=1
}

# _doc_cmd <command> <required:1|0> <why>
_doc_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    _doc_ok "$1 ($3)"
  elif [ "$2" = 1 ]; then
    _doc_fail "$1 not found ($3)"
  else
    _doc_warn "$1 not found ($3; optional)"
  fi
}

doctor_main() {
  _DOC_FAILED=0
  printf 'orchestra %s (%s)\n\nMachine:\n' "$(cat "$ORCHESTRA_HOME/VERSION")" "$ORCHESTRA_HOME"
  _doc_cmd git 1 "worktrees and branches"
  _doc_cmd jq 1 "all JSON state"
  if command -v jq >/dev/null 2>&1 && ! jq -n --rawfile x /dev/null '1' >/dev/null 2>&1; then
    _doc_fail "jq $(jq --version) is too old (need 1.6+ for --rawfile)"
  fi
  _doc_cmd check-jsonschema 1 "schema validation"
  _doc_cmd claude 1 "phase 1, reviewer and confirmer"
  _doc_cmd tmux 0 "orchestra design cockpit"
  if command -v redocly >/dev/null 2>&1 || command -v swagger-cli >/dev/null 2>&1; then
    _doc_ok "OpenAPI validator (full api_spec check)"
  else
    _doc_warn "no redocly or swagger-cli (api_spec readiness uses a light check; optional)"
  fi

  _root=$(project_root)
  if [ ! -f "$_root/orchestra.config.json" ]; then
    printf '\nNot inside an orchestra project (no orchestra.config.json in %s).\n' "$_root"
    printf 'Run orchestra init there to start one.\n'
    return "$_DOC_FAILED"
  fi

  printf '\nProject %s:\n' "$_root"
  if git -C "$_root" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    _doc_ok "git repository with commits"
  else
    _doc_fail "not a git repository with at least one commit (orchestra go needs one)"
  fi
  if _cv=$(config_validate 2>&1); then
    _doc_ok "orchestra.config.json is valid"
    if [ -n "$_cv" ]; then _doc_warn "$_cv"; fi
    _wsr=$(config_get '.repos // {} | to_entries[] | "\(.key) (\(.value.path)/)"' | paste -sd, - | sed 's/,/, /g')
    if [ -n "$_wsr" ]; then _doc_ok "workspace: root + $_wsr"; fi
  else
    _doc_fail "orchestra.config.json: $_cv"
    return 1
  fi
  _rev=$(brain_cmd reviewer 2>/dev/null | awk '{ print $1 }')
  if [ -n "$_rev" ] && command -v "$_rev" >/dev/null 2>&1; then
    _doc_ok "brain.reviewer: $_rev"
  else
    _doc_fail "brain.reviewer command not found: ${_rev:-unset}"
  fi
  for _a in $(config_get '.agents[].name'); do
    _ad=$(agent_field "$_a" '.adapter')
    if [ ! -f "$ORCHESTRA_HOME/adapters/$_ad.sh" ]; then
      _doc_fail "agent $_a: no adapter $_ad"
    elif ( pool_spawn "$_a" ) >/dev/null 2>&1; then
      _doc_ok "agent $_a ($_ad) is available; skills: $(pool_skills "$_a" | tr '\n' ' ')"
    else
      _doc_fail "agent $_a ($_ad): its CLI is not available"
    fi
  done
  if [ -f "$_root/plan.json" ]; then
    if [ "$(jq -r '.approved' "$_root/plan.json")" = true ]; then
      _doc_ok "plan.json approved ($(jq '.tasks | length' "$_root/plan.json") tasks)"
    else
      _doc_warn "plan.json not approved yet (run /go in Claude or orchestra go)"
    fi
  else
    _doc_warn "no plan.json yet (phase 1: /breakdown then /plan)"
  fi
  return "$_DOC_FAILED"
}
