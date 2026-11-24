#!/usr/bin/env bats
# Runner VERIFY: done_when is evaluated by running real commands in the worktree.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export ORCHESTRA_HOME="$ROOT"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/work/t"
  printf 'exit 0\n' > "$PROJ/work/t/pass.sh"
  printf 'exit 1\n' > "$PROJ/work/t/fail.sh"
  cat > "$PROJ/orchestra.config.json" <<'JSON'
{
  "orchestra_version": "0.1.0", "project": "t", "profile": "standard",
  "stack": { "language": "sh", "test": "true", "test_one": "sh {files}",
             "typecheck": "true", "build": "false" },
  "brain": { "planner": "claude", "reviewer": "claude -p" },
  "agents": [ { "name": "m", "adapter": "mock", "skills": ["backend"] } ]
}
JSON
  cat > "$PROJ/plan.json" <<'JSON'
{
  "orchestra_version": "0.1.0", "goal": "t", "approved": false,
  "tasks": [
    { "id": "T1", "done_when": { "tests_pass": ["t/pass.sh"], "typecheck": true } },
    { "id": "T2", "done_when": { "tests_pass": ["t/fail.sh"] } },
    { "id": "T3", "done_when": { "tests_pass": ["t/pass.sh"], "build": true } },
    { "id": "T4", "done_when": { "tests_pass": ["t/pass.sh"], "commands": ["test -f marker"] } },
    { "id": "T5", "done_when": { "tests_pass": ["t/pass.sh", "t/fail.sh"] } }
  ]
}
JSON
  cd "$PROJ"
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/config.sh"
  . "$ROOT/lib/runner.sh"
}

report() { jq -r "$1" "$PROJ/.bus/verify/$2.json"; }

@test "passing task: tests + typecheck pass and the report is schema-valid" {
  run runner_verify T1 "$PROJ/work"
  [ "$status" -eq 0 ]
  [ "$(report '.passed' T1)" = "true" ]
  [ "$(report '[.checks[].name] | join(",")' T1)" = "tests,typecheck" ]
  [ "$(report '.checks[0].cmd' T1)" = "sh t/pass.sh" ]
  check-jsonschema --schemafile "$ROOT/schemas/verify.schema.json" "$PROJ/.bus/verify/T1.json"
}

@test "failing test fails the task" {
  run runner_verify T2 "$PROJ/work"
  [ "$status" -ne 0 ]
  [ "$(report '.passed' T2)" = "false" ]
  [ "$(report '.checks[0].exit' T2)" = "1" ]
}

@test "failing build fails the task" {
  run runner_verify T3 "$PROJ/work"
  [ "$status" -ne 0 ]
  [ "$(report '.checks[] | select(.name=="build") | .passed' T3)" = "false" ]
}

@test "extra commands count: fail without the marker, pass with it" {
  run runner_verify T4 "$PROJ/work"
  [ "$status" -ne 0 ]
  touch "$PROJ/work/marker"
  run runner_verify T4 "$PROJ/work"
  [ "$status" -eq 0 ]
}

@test "{files} is replaced by the space-separated test list" {
  run runner_verify T5 "$PROJ/work"
  [ "$(report '.checks[0].cmd' T5)" = "sh t/pass.sh t/fail.sh" ]
}

@test "typecheck requested but stack.typecheck unset is an error" {
  jq 'del(.stack.typecheck)' orchestra.config.json > c && mv c orchestra.config.json
  run runner_verify T1 "$PROJ/work"
  [ "$status" -ne 0 ]
  [[ "$output" == *"stack.typecheck is unset"* ]]
}
