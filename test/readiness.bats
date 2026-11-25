#!/usr/bin/env bats
# Design readiness check, run against a copy of examples/blog-api and against
# copies broken in exactly one way.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export ORCHESTRA_HOME="$ROOT"
  PROJ="$BATS_TEST_TMPDIR/proj"
  cp -R "$ROOT/examples/blog-api" "$PROJ"
  cd "$PROJ"
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/config.sh"
  . "$ROOT/lib/readiness.sh"
}

# edit <file> <sed-expr> — portable in-place sed.
edit() { sed "$2" "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
plan_edit() { jq "$1" plan.json > p && mv p plan.json; }

@test "the example passes every profile" {
  for p in lite standard strict; do
    run readiness_check "$p"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  done
}

@test "standard skips data_model, strict runs it" {
  run readiness_check standard
  [[ "$output" == *"SKIP  data_model"* ]]
  run readiness_check strict
  [[ "$output" == *"PASS  data_model"* ]]
}

@test "coverage: an FR missing from traceability fails" {
  printf '\n### FR-9: Extra\n\n- Acceptance: x\n' >> docs/01-SRS.md
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL  coverage"* ]]
  [[ "$output" == *"FR-9 is in the SRS but not in traceability.json"* ]]
}

@test "coverage: a task serving no FR fails" {
  plan_edit '.tasks += [{"id":"T6","desc":"x","deps":[],"skill":"api","spec_file":"docs/specs/T6.md","done_when":{"tests_pass":["test/posts.list.test.ts"]}}]'
  cp docs/specs/T5.md docs/specs/T6.md
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"T6 serves no FR in traceability.json"* ]]
}

@test "testability: an FR without a test-plan section fails" {
  edit docs/06-test-plan.md 's/^### FR-4$/### Listing/'
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL  testability"* ]]
  [[ "$output" == *"FR-4 has no '### FR-4' section"* ]]
}

@test "testability: a done_when test missing from traceability fails" {
  plan_edit '.tasks[4].done_when.tests_pass += ["test/extra.test.ts"]'
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"test/extra.test.ts (plan.json done_when) is not in traceability.json"* ]]
}

@test "rationale: a referenced ADR without a file fails; lite skips the check" {
  rm docs/03-adr/0002-*.md
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"ADR-0002 is referenced but"* ]]
  run readiness_check lite
  [ "$status" -eq 0 ]
}

@test "api_spec: a spec with no top-level paths fails" {
  edit docs/04-api-spec.yaml 's/^paths:/routes:/'
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL  api_spec"* ]]
}

@test "api_spec: the light check says so when no validator is installed" {
  if command -v redocly >/dev/null || command -v swagger-cli >/dev/null; then
    skip "a full OpenAPI validator is installed"
  fi
  run readiness_check standard
  [[ "$output" == *"NOTE  api_spec: light check only"* ]]
}

@test "data_model: a schema not mentioned fails under strict" {
  edit docs/05-data-model.md '/^| Token |/d'
  run readiness_check strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"schema Token (components.schemas) is not mentioned"* ]]
}

@test "nfr: a requirement with an empty target fails" {
  edit docs/07-nfr.md 's/^| Structured logs | [^|]*|/| Structured logs |  |/'
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"NFR-3 has no measurable target"* ]]
}

@test "review_brief: a missing brief fails" {
  rm docs/09-review-brief.md
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing or empty docs/09-review-brief.md"* ]]
}

@test "plan_schema: a missing spec file fails" {
  rm docs/specs/T5.md
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"T5: docs/specs/T5.md does not exist"* ]]
}

@test "plan_schema: an unknown dependency fails" {
  plan_edit '.tasks[1].deps = ["T9"]'
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"T2 depends on unknown task T9"* ]]
}

@test "plan_schema: a dependency cycle fails" {
  plan_edit '.tasks[0].deps = ["T5"]'
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"dependency cycle among:"* ]]
}

@test "plan_schema: a schema violation fails" {
  plan_edit 'del(.tasks[0].done_when)'
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan.json does not match schemas/plan.schema.json"* ]]
}

@test "an unknown profile is an error" {
  run readiness_check yolo
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown profile: yolo"* ]]
}

cfg_web() { jq '.repos = {"web": {"path": "web", "stack": .stack}}' orchestra.config.json > c && mv c orchestra.config.json; }

@test "plan_schema: a task naming an unconfigured repo fails" {
  plan_edit '.tasks[0].repos = ["root", "web"]'
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"T1: repo web is not configured"* ]]
}

@test "plan_schema: scope outside the task's repos fails" {
  cfg_web
  plan_edit '.tasks[0].repos = ["web"]'
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"T1: src/db/** is in repo root, which is not in its repos (web)"* ]]
  [[ "$output" == *"T1: test/user.model.test.ts is in repo root"* ]]
}

@test "plan_schema: a task spanning root and a repo passes" {
  cfg_web
  plan_edit '.tasks[0].repos = ["root", "web"] | .tasks[0].scope += ["web/src/**"]'
  run readiness_check standard
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "plan_schema: a path in an unlisted repo fails" {
  cfg_web
  plan_edit '.tasks[0].scope += ["web/src/**"]'
  run readiness_check standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"T1: web/src/** is in repo web, which is not in its repos (root)"* ]]
}
