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
