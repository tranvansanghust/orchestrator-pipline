# shellcheck shell=sh
# DESIGN READINESS CHECK — blocks `orchestra go` until phase-1 artifacts are
# complete. Which checks run depends on the profile (profiles/<name>.json):
#
#   coverage       every FR in the SRS maps to >= 1 task
#   testability    every task has >= 1 acceptance test
#   rationale      every major decision has an ADR
#   api_spec       docs/04-api-spec.yaml is valid OpenAPI
#   data_model     data model consistent with api-spec
#   nfr            NFRs have measurable criteria
#   review_brief   docs/09-review-brief.md exists
#   plan_schema    plan.json validates against schemas/plan.schema.json

# readiness_check [profile] — run the profile's checks, print every gap,
# return non-zero if any check fails.
readiness_check() { not_implemented readiness_check; }
