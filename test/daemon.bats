#!/usr/bin/env bats
# Phase 2 end to end, offline: `orchestra go` on a tiny two-task project with
# the mock agent (scripted per task through ORCHESTRA_MOCK_CMD; $1 = task id,
# $2 = prompt file) and the fake reviewer.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ORCHESTRA="$ROOT/bin/orchestra"
  FAKE="$ROOT/test/fixtures/fake-claude"
  export FAKE_LOG="$BATS_TEST_TMPDIR/calls"
  export SETUP_LOG="$BATS_TEST_TMPDIR/setup.log"
  PROJ="$BATS_TEST_TMPDIR/proj"
  export PROJ
  mkdir -p "$PROJ/docs/specs"
  cd "$PROJ"

  jq -n --arg f "$FAKE -p" '{
    orchestra_version: "0.1.0", project: "p", profile: "lite",
    stack: { language: "sh", test: "true",
             test_one: "for f in {files}; do sh \"$f\" || exit 1; done",
             setup: "echo ran >> \"$SETUP_LOG\"" },
    brain: { planner: "claude", reviewer: $f, confirmer: $f },
    agents: [ { name: "m", adapter: "mock", skills: ["backend"] } ],
    escalation: { confidence_threshold: 0.75, always_human: ["auth"],
                  max_verify_rounds: 2, max_reject_rounds: 2 },
    execution: { agent_timeout_s: 20 }
  }' > orchestra.config.json
  jq -n '{
    orchestra_version: "0.1.0", goal: "g", approved: false,
    tasks: [
      { id: "T1", desc: "first", deps: [], skill: "backend", spec_file: "docs/specs/T1.md",
        areas: [], done_when: { tests_pass: ["t/T1.sh"] } },
      { id: "T2", desc: "second", deps: ["T1"], skill: "backend", spec_file: "docs/specs/T2.md",
        areas: [], done_when: { tests_pass: ["t/T2.sh"] } }
    ]
  }' > plan.json
  jq -n '{
    "FR-1": { desc: "one", tasks: ["T1"], tests: ["t/T1.sh"], acceptance: "a1", status: "planned" },
    "FR-2": { desc: "two", tasks: ["T2"], tests: ["t/T2.sh"], acceptance: "a2", status: "planned" }
  }' > traceability.json
  printf '# SRS\n\n### FR-1: one\n\n### FR-2: two\n' > docs/01-SRS.md
  printf '# Test plan\n\n### FR-1\n\n### FR-2\n' > docs/06-test-plan.md
  printf '# T1\n\nDo the first thing.\n' > docs/specs/T1.md
  printf '# T2\n\nDo the second thing.\n' > docs/specs/T2.md
  printf '.bus/\n.worktrees/\n' > .gitignore
  git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init
  START_BRANCH=$(git rev-parse --abbrev-ref HEAD)

  export ORCHESTRA_MOCK_CMD='mkdir -p t && printf "exit 0\n" > "t/$1.sh" && printf "%s\n" "$1" > "impl-$1.txt"'
  export FAKE_REVIEWER_JSON='{"task":"__TASK__","verdict":"ACCEPT","confidence":0.9,"summary":"ok","evidence":[{"claim":"tests pass","source":"verify_report"}],"needs_human":false}'
  export FAKE_CONFIRMER_JSON='{"task":"__TASK__","upheld":true,"supported":"ACCEPT","reason":"r"}'
}

state() { jq -r '.state' ".bus/tasks/$1.json" 2>/dev/null || echo DRAFT; }
field() { jq -r "$2" ".bus/tasks/$1.json"; }
plan_edit() { jq "$1" plan.json > p && mv p plan.json && git add plan.json && git -c user.email=t@t -c user.name=t commit -qm edit; }

@test "happy path: both tasks merged into orchestra/run, user's branch untouched" {
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state T1)" = DONE ]
  [ "$(state T2)" = DONE ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "$START_BRANCH" ]
  [ ! -f impl-T1.txt ]
  [ "$(git show orchestra/run:impl-T1.txt)" = T1 ]
  [ "$(git show orchestra/run:impl-T2.txt)" = T2 ]
  [ "$(git show orchestra/run:plan.json | jq -r .approved)" = true ]
  [ "$(git log orchestra/run --merges --oneline | wc -l | tr -d ' ')" -eq 2 ]
  [ "$(grep -c ran "$SETUP_LOG")" -eq 2 ]
  [ ! -d .worktrees/T1 ]
  [ "$(jq -r '.["FR-1"].status' .bus/traceability.status.json)" = accepted ]
  [ "$(grep -c '"event":"transition"' .bus/log.jsonl)" -gt 10 ]
  check-jsonschema --schemafile "$ROOT/schemas/task.schema.json" .bus/tasks/T1.json
  [[ "$output" == *"Run finished: 2 done"* ]]
}

@test "T2 starts from T1's merged work" {
  export ORCHESTRA_MOCK_CMD='mkdir -p t && printf "exit 0\n" > "t/$1.sh" && { [ "$1" = T1 ] || [ -f impl-T1.txt ]; } && printf "%s\n" "$1" > "impl-$1.txt"'
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(git show orchestra/run:impl-T2.txt)" = T2 ]
}

@test "the agent prompt carries spec, requirement, done_when and scope" {
  plan_edit '.tasks[0].scope = ["src/**"]'
  run "$ORCHESTRA" go
  p=.bus/tasks/T1/prompt-1.md
  grep -q '^# Task T1: first' "$p"
  grep -q 'Do the first thing.' "$p"
  grep -q 'FR-1: one. Acceptance: a1' "$p"
  grep -q 'for f in t/T1.sh' "$p"
  grep -q -- '- src/\*\*' "$p"
}

@test "VERIFY failure goes back to the agent with the failing output" {
  export ORCHESTRA_MOCK_CMD='mkdir -p t; if grep -q "failed verification" "$2"; then printf "exit 0\n" > "t/$1.sh"; else printf "echo boom-%s; exit 1\n" "$1" > "t/$1.sh"; fi'
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state T1)" = DONE ]
  [ "$(field T1 .verify_rounds)" = 1 ]
  grep -q 'Previous attempt failed verification' .bus/tasks/T1/prompt-2.md
  grep -q 'boom-T1' .bus/tasks/T1/prompt-2.md
}

@test "VERIFY failing max_verify_rounds times blocks the task; dependents wait" {
  export ORCHESTRA_MOCK_CMD='mkdir -p t; printf "exit 1\n" > "t/$1.sh"'
  run "$ORCHESTRA" go
  [ "$status" -eq 4 ]
  [ "$(state T1)" = BLOCKED ]
  [ "$(state T2)" = DRAFT ]
  grep -q 'VERIFY failed 2 times' .bus/escalations/T1.md
  [[ "$output" == *"1 blocked, 0 escalated, 1 waiting"* ]]
  [[ "$output" == *".bus/escalations/T1.md"* ]]
}

@test "an agent that times out is stopped and told so" {
  jq '.execution.agent_timeout_s = 1' orchestra.config.json > c && mv c orchestra.config.json
  git add -A && git -c user.email=t@t -c user.name=t commit -qm t
  export ORCHESTRA_MOCK_CMD='sleep 5'
  run "$ORCHESTRA" go
  [ "$status" -eq 4 ]
  [ "$(state T1)" = BLOCKED ]
  [ "$(field T1 .agent_rc)" = 124 ]
  grep -q 'hit the time limit (1s)' .bus/tasks/T1/prompt-2.md
}

@test "REJECT goes back to the agent with the fixes, then ACCEPT" {
  export FAKE_REVIEWER_JSON_T1_R1='{"task":"T1","verdict":"REJECT","confidence":0.9,"summary":"needs work","evidence":[{"claim":"x","source":"diff"}],"needs_human":false,"fixes_requested":["rename the helper"]}'
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state T1)" = DONE ]
  [ "$(field T1 .reject_rounds)" = 1 ]
  grep -q 'rename the helper' .bus/tasks/T1/prompt-2.md
}

@test "REJECT max_reject_rounds times escalates" {
  export FAKE_REVIEWER_JSON_T1='{"task":"T1","verdict":"REJECT","confidence":0.9,"summary":"no","evidence":[{"claim":"x","source":"diff"}],"needs_human":false,"fixes_requested":["again"]}'
  run "$ORCHESTRA" go
  [ "$status" -eq 4 ]
  [ "$(state T1)" = ESCALATED ]
  grep -q 'REJECTED 2 times' .bus/escalations/T1.md
}

@test "an always_human area escalates instead of merging" {
  plan_edit '.tasks[0].areas = ["auth"]'
  run "$ORCHESTRA" go
  [ "$status" -eq 4 ]
  [ "$(state T1)" = ESCALATED ]
  grep -q 'always_human' .bus/escalations/T1.md
  ! git show orchestra/run:impl-T1.txt 2>/dev/null
}

@test "no agent for the task's skill blocks it" {
  plan_edit '.tasks[0].skill = "frontend"'
  run "$ORCHESTRA" go
  [ "$status" -eq 4 ]
  [ "$(state T1)" = BLOCKED ]
  grep -q 'advertises skill "frontend"' .bus/escalations/T1.md
}

@test "stop mid-run, then go resumes where it left off" {
  export ORCHESTRA_MOCK_CMD='mkdir -p t && printf "exit 0\n" > "t/$1.sh" && printf "%s\n" "$1" > "impl-$1.txt"; [ "$1" = T1 ] && touch "$PROJ/.bus/stop"; true'
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ]
  [[ "$output" == *"Stopped:"* ]]
  [ "$(state T1)" != DONE ]
  [ "$(state T2)" = DRAFT ]
  export ORCHESTRA_MOCK_CMD='mkdir -p t && printf "exit 0\n" > "t/$1.sh" && printf "%s\n" "$1" > "impl-$1.txt"'
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"Design unchanged since"* ]]
  [ "$(state T1)" = DONE ]
  [ "$(state T2)" = DONE ]
  [ ! -f .bus/tasks/T1/prompt-2.md ]
}

@test "orchestra stop sets the stop flag" {
  run "$ORCHESTRA" stop
  [ "$status" -eq 0 ]
  [ -f .bus/stop ]
}

@test "orchestra status shows tasks, requirements and the inbox" {
  export ORCHESTRA_MOCK_CMD='mkdir -p t; printf "exit 1\n" > "t/$1.sh"'
  "$ORCHESTRA" go >/dev/null || true
  run "$ORCHESTRA" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"T1    BLOCKED"* ]]
  [[ "$output" == *"T2    DRAFT"* ]]
  [[ "$output" == *"FR-1  planned"* ]]
  [[ "$output" == *".bus/escalations/T1.md"* ]]
}

@test "go needs a git repository" {
  rm -rf .git
  run "$ORCHESTRA" go
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs a git repository"* ]]
}
