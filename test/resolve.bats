#!/usr/bin/env bats
# `orchestra resolve`: accept, reject, retry, amend-spec, handoff.

load helpers/project

setup() {
  make_project
  export FAKE_PLANNER_LOG="$BATS_TEST_TMPDIR/planner.log"
}

escalate_t1() { # make T1 escalate through the always_human rule
  plan_edit '.tasks[0].areas = ["auth"]'
  "$ORCHESTRA" go >/dev/null 2>&1 || true
  [ "$(state T1)" = ESCALATED ]
}

block_t1() { # make T1 fail VERIFY until blocked
  ORCHESTRA_MOCK_CMD='mkdir -p t; printf "exit 1\n" > "t/$1.sh"' "$ORCHESTRA" go >/dev/null 2>&1 || true
  [ "$(state T1)" = BLOCKED ]
}

@test "accept merges an escalated change; go then finishes the plan" {
  escalate_t1
  run "$ORCHESTRA" resolve T1 accept
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state T1)" = DONE ]
  [ "$(git show orchestra/run:impl-T1.txt)" = T1 ]
  [ ! -f .bus/escalations/T1.md ]
  ls .bus/escalations/resolved/T1-*.md
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state T2)" = DONE ]
}

@test "accept refuses a BLOCKED task" {
  block_t1
  run "$ORCHESTRA" resolve T1 accept
  [ "$status" -ne 0 ]
  [[ "$output" == *"use retry or reject"* ]]
}

@test "accept refuses while a run is active" {
  escalate_t1
  sleep 30 &
  printf '%s\n' "$!" > .bus/run.pid
  run "$ORCHESTRA" resolve T1 accept
  kill %1 2>/dev/null || true
  [ "$status" -ne 0 ]
  [[ "$output" == *"run is active"* ]]
}

@test "reject sends the task back with the message and a fresh budget" {
  escalate_t1
  run "$ORCHESTRA" resolve T1 reject "use a constant instead"
  [ "$status" -eq 0 ]
  [ "$(state T1)" = DRAFT ]
  [ "$(field T1 .reject_rounds)" = 0 ]
  "$ORCHESTRA" go >/dev/null 2>&1 || true
  grep -q 'use a constant instead' .bus/tasks/T1/prompt-2.md
}

@test "reject needs a message" {
  escalate_t1
  run "$ORCHESTRA" resolve T1 reject
  [ "$status" -ne 0 ]
}

@test "retry unblocks a BLOCKED task once the problem is fixed" {
  block_t1
  run "$ORCHESTRA" resolve T1 retry "fixed the env"
  [ "$status" -eq 0 ]
  [ "$(state T1)" = DRAFT ]
  [ "$(field T1 .verify_rounds)" = 0 ]
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state T1)" = DONE ]
  [ "$(state T2)" = DONE ]
}

@test "amend-spec needs an edited design" {
  escalate_t1
  run "$ORCHESTRA" resolve T1 amend-spec "clarified"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no design change since the freeze"* ]]
}

@test "amend-spec re-freezes the design and restarts the task from scratch" {
  escalate_t1
  plan_edit '.tasks[0].areas = []'
  printf '# T1\n\nDo the first thing, clarified.\n' > docs/specs/T1.md
  run "$ORCHESTRA" resolve T1 amend-spec "auth is not involved after all"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state T1)" = DRAFT ]
  [ ! -d .worktrees/T1 ]
  ! git show-ref --verify -q refs/heads/orchestra/T1
  [ "$(git show orchestra/run:docs/specs/T1.md | tail -1)" = "Do the first thing, clarified." ]
  [ "$(jq -r '.files["docs/specs/T1.md"]' .bus/frozen.json)" = "$(shasum -a 256 docs/specs/T1.md | cut -d' ' -f1)" ]
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state T1)" = DONE ]
  [ "$(state T2)" = DONE ]
  p=$(ls .bus/tasks/T1/prompt-*.md | sort -t- -k2 -n | tail -1)
  grep -q 'auth is not involved after all' "$p"
  grep -q 'clarified' "$p"
}

@test "resolve without an action opens Claude with the escalation loaded" {
  escalate_t1
  run env ORCHESTRA_NO_TMUX=1 "$ORCHESTRA" resolve T1
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qx "cwd=$(cd "$PROJ" && pwd -P)" "$FAKE_PLANNER_LOG" || grep -qx "cwd=$PROJ" "$FAKE_PLANNER_LOG"
  grep -q 'Task T1 of this orchestra project stopped' "$FAKE_PLANNER_LOG"
  grep -q 'always_human' "$FAKE_PLANNER_LOG"
}

@test "only BLOCKED or ESCALATED tasks can be resolved" {
  run "$ORCHESTRA" resolve T1 retry
  [ "$status" -ne 0 ]
  [[ "$output" == *"T1 is DRAFT"* ]]
  run "$ORCHESTRA" resolve T9 retry
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown task: T9"* ]]
}

@test "unknown action is a usage error" {
  escalate_t1
  run "$ORCHESTRA" resolve T1 yolo
  [ "$status" -eq 2 ]
}
