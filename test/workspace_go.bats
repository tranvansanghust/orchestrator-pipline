#!/usr/bin/env bats
# Phase 2 on a workspace (ADR-0013), offline: root plus child repo web/.
# T1 may change root and web, with its test in web; T2 (deps T1) only root.

load helpers/project

setup() {
  make_workspace
  jq '.repos.web.stack.setup = "echo web >> \"$SETUP_LOG\""
      | .stack.integration = "test -f web/impl.txt && test -f impl-T2.txt"' \
    orchestra.config.json > c && mv c orchestra.config.json
  plan_edit '.tasks[0].repos = ["root", "web"] | .tasks[0].done_when.tests_pass = ["web/t/T1.sh"]'
  jq '.["FR-1"].tests = ["web/t/T1.sh"]' traceability.json > tr && mv tr traceability.json
  export ORCHESTRA_MOCK_CMD='if [ "$1" = T1 ]; then
      mkdir -p web/t && printf "exit 0\n" > web/t/T1.sh && printf "T1\n" > web/impl.txt
    else
      mkdir -p t && printf "exit 0\n" > "t/$1.sh" && printf "%s\n" "$1" > "impl-$1.txt"
    fi'
}

@test "a task spanning two repos lands on orchestra/run in both" {
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state T1)" = DONE ] && [ "$(state T2)" = DONE ]
  [ "$(git -C web show orchestra/run:impl.txt)" = T1 ]
  [ "$(git show orchestra/run:impl-T2.txt)" = T2 ]
  ! git show orchestra/run:web/impl.txt 2>/dev/null
  [ ! -f web/impl.txt ]
  # Per task checkout (root: T1, T2; web: T1), then each repo of _run for the
  # integration build.
  [ "$(grep -c ran "$SETUP_LOG")" -eq 3 ]
  [ "$(grep -c web "$SETUP_LOG")" -eq 2 ]
  [ "$(jq -r '.checks[0].repo' .bus/verify/T1.json)" = web ]
  [[ "$(jq -r '.checks[0].cmd' .bus/verify/T1.json)" == *" t/T1.sh;"* ]]
  check-jsonschema --schemafile "$ROOT/schemas/verify.schema.json" .bus/verify/T1.json
  check-jsonschema --schemafile "$ROOT/schemas/task.schema.json" .bus/tasks/T1.json
  [[ "$output" == *"Integration build passed"* ]]
}

@test "the prompt says which repos the task may change" {
  run "$ORCHESTRA" go
  grep -q '^## Repositories' .bus/tasks/T1/prompt-1.md
  grep -q -- '- web/: you may change it' .bus/tasks/T1/prompt-1.md
  grep -q -- '- tests, in web: `' .bus/tasks/T1/prompt-1.md
  grep -q -- '- web/: read only' .bus/tasks/T2/prompt-1.md
}

@test "changes in a read-only repo are discarded and fail VERIFY until BLOCKED" {
  export ORCHESTRA_MOCK_CMD="$ORCHESTRA_MOCK_CMD"'
    [ "$1" = T2 ] && printf "x\n" > web/hack.txt; true'
  run "$ORCHESTRA" go
  [ "$status" -eq 4 ] || { echo "$output"; return 1; }
  [ "$(state T1)" = DONE ]
  [ "$(state T2)" = BLOCKED ]
  [ "$(jq -r '.checks[0].name' .bus/verify/T2.json)" = scope ]
  grep -q 'web/hack.txt' .bus/tasks/T2/prompt-2.md
  ! git -C web show orchestra/run:hack.txt 2>/dev/null
  [ ! -e .worktrees/T2/web/hack.txt ]
}

@test "orchestra finds the workspace from inside a child repo" {
  "$ORCHESTRA" go --no-run >/dev/null
  cd web
  run "$ORCHESTRA" status
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"REPOS"* ]]
  [[ "$output" == *"root,web"* ]]
}

@test "the workspace example builds and passes the readiness check" {
  sh "$ROOT/examples/workspace/make-demo.sh" "$BATS_TEST_TMPDIR/demo"
  cd "$BATS_TEST_TMPDIR/demo"
  run "$ORCHESTRA" go --no-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"PASS  plan_schema"* ]]
  [ "$(git -C api rev-parse --abbrev-ref HEAD)" != orchestra/run ]
}
