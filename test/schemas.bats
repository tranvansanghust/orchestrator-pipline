#!/usr/bin/env bats
# Schemas accept the shipped example and reject the mistakes they exist to catch.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  EX="$ROOT/examples/blog-api"
}

# valid <schema> <file> / invalid <schema> <jq-mutation> <base-file>
valid() {
  check-jsonschema --schemafile "$ROOT/schemas/$1.schema.json" "$2"
}

invalid() {
  jq "$2" "$3" > "$BATS_TEST_TMPDIR/mutated.json"
  run check-jsonschema --schemafile "$ROOT/schemas/$1.schema.json" "$BATS_TEST_TMPDIR/mutated.json"
  [ "$status" -ne 0 ]
}

@test "example plan, config and traceability are valid" {
  valid plan "$EX/plan.json"
  valid config "$EX/orchestra.config.json"
  valid traceability "$EX/traceability.json"
}

@test "plan: a task without done_when is rejected" {
  invalid plan 'del(.tasks[0].done_when)' "$EX/plan.json"
}

@test "plan: done_when with no tests is rejected" {
  invalid plan '.tasks[0].done_when.tests_pass = []' "$EX/plan.json"
}

@test "plan: spec_file outside docs/specs is rejected" {
  invalid plan '.tasks[0].spec_file = ".bus/specs/T1.md"' "$EX/plan.json"
}

@test "plan: a build block is rejected (commands live in the config)" {
  invalid plan '.build = {"cmd": "npm run build"}' "$EX/plan.json"
}

@test "plan: malformed task id is rejected" {
  invalid plan '.tasks[0].id = "task-1"' "$EX/plan.json"
}

@test "config: test_one without {files} is rejected" {
  invalid config '.stack.test_one = "npx vitest run"' "$EX/orchestra.config.json"
}

@test "config: unknown profile is rejected" {
  invalid config '.profile = "yolo"' "$EX/orchestra.config.json"
}

@test "config: unknown gate action is rejected" {
  invalid config '.vcs.gate = ["push", "rm-rf"]' "$EX/orchestra.config.json"
}

@test "traceability: non-FR key is rejected" {
  invalid traceability '. + {"REQ-9": .["FR-1"]}' "$EX/traceability.json"
}

@test "traceability: unknown status is rejected" {
  invalid traceability '.["FR-1"].status = "done"' "$EX/traceability.json"
}

@test "sample verdicts and confirmations are valid" {
  for f in "$EX"/samples/verdict-*.json; do valid verdict "$f"; done
  for f in "$EX"/samples/confirmation-*.json; do valid confirmation "$f"; done
}

@test "verdict: unknown evidence source is rejected" {
  invalid verdict '.evidence[0].source = "gut_feeling"' "$EX/samples/verdict-T3-accept.json"
}

@test "verdict: evidence must not be empty" {
  invalid verdict '.evidence = []' "$EX/samples/verdict-T3-accept.json"
}

@test "verdict: REJECT without fixes_requested is rejected" {
  invalid verdict 'del(.fixes_requested)' "$EX/samples/verdict-T5-reject.json"
}

@test "verdict: needs_human without a question is rejected" {
  invalid verdict '.question_for_human = null | del(.question_for_human)' "$EX/samples/verdict-T3-escalate.json"
}

@test "verdict: unknown verdict value is rejected" {
  invalid verdict '.verdict = "MAYBE"' "$EX/samples/verdict-T3-accept.json"
}

@test "confirmation: unknown supported value is rejected" {
  invalid confirmation '.supported = "MERGE"' "$EX/samples/confirmation-T5-upheld.json"
}

@test "config: brain.confirmer may pin a model" {
  jq '.brain.confirmer = {"cmd": "claude -p", "model": "claude-haiku-4-5-20251001"}' \
    "$EX/orchestra.config.json" > "$BATS_TEST_TMPDIR/c.json"
  valid config "$BATS_TEST_TMPDIR/c.json"
}

@test "config: brain role object without cmd is rejected" {
  invalid config '.brain.reviewer = {"model": "x"}' "$EX/orchestra.config.json"
}
