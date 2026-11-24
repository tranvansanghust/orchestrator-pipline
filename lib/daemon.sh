# shellcheck shell=sh
# Phase-2 daemon: SCHEDULE -> SPAWN -> CODE -> VERIFY -> REVIEW -> MERGE,
# looping until the DAG is drained. Destructive actions (push, deploy,
# delete, migration) always stop at a gate.

# go_main [--profile P] — `orchestra go`: run the readiness check, mark the
# plan approved and freeze the phase-1 artifacts (ADR-0007). Starting the
# execution loop comes with the daemon (roadmap step 4).
go_main() {
  _profile=""
  while [ $# -gt 0 ]; do
    case $1 in
      --profile)
        [ $# -ge 2 ] || { printf 'orchestra go: --profile needs a value\n' >&2; exit "$ORCHESTRA_EXIT_USAGE"; }
        _profile=$2
        shift 2
        ;;
      --profile=*) _profile=${1#*=}; shift ;;
      *)
        printf 'orchestra go: unknown option: %s\n' "$1" >&2
        exit "$ORCHESTRA_EXIT_USAGE"
        ;;
    esac
  done
  [ -n "$_profile" ] || _profile=$(config_get '.profile')

  readiness_check "$_profile" \
    || die "readiness check failed; fix the gaps above, then run orchestra go again"

  _root=$(project_root)
  _plan=$(plan_path)
  jq '.approved = true' "$_plan" >"$_plan.tmp" && mv "$_plan.tmp" "$_plan"

  # Freeze manifest: sha256 of every phase-1 artifact, so phase 2 can detect
  # edits made after approval.
  mkdir -p "$(bus_dir)"
  (
    cd "$_root" || exit 1
    { find docs -type f | LC_ALL=C sort; printf 'plan.json\ntraceability.json\n'; } \
      | while IFS= read -r _f; do
          [ -f "$_f" ] || continue
          jq -nc --arg f "$_f" --arg h "$(sha256 "$_f")" '{($f): $h}'
        done
  ) | jq -s --arg at "$(now_iso)" --arg p "$_profile" \
    '{frozen_at: $at, profile: $p, files: add}' >"$(bus_dir)/frozen.json"

  _n=$(jq '.files | length' "$(bus_dir)/frozen.json")
  printf '\nApproved: plan.json marked approved, %s artifacts frozen in .bus/frozen.json.\n' "$_n"
  printf 'Commit docs/, plan.json and traceability.json now so the frozen design is in history.\n'
  printf 'The phase-2 execution loop is not implemented yet (roadmap step 4).\n'
}

# daemon_loop — the main execution loop.
daemon_loop() { not_implemented daemon_loop; }

# daemon_stop — `orchestra stop`: stop the daemon, leave state in .bus/.
daemon_stop() { not_implemented stop; }
