#!/usr/bin/env bats
# zcode adapter, offline: ORCHESTRA_ZCODE_BIN points at a fake CLI.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export ORCHESTRA_HOME="$ROOT"
  export ORCHESTRA_ZCODE_BIN="$ROOT/test/fixtures/fake-zcode"
  export FAKE_ZCODE_LOG="$BATS_TEST_TMPDIR/zcode.args"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/work"
  cd "$PROJ"
  jq -n '{
    orchestra_version: "0.1.0", project: "t", profile: "standard",
    stack: { language: "sh", test: "true", test_one: "true {files}" },
    brain: { planner: "claude", reviewer: "claude -p" },
    agents: [ { name: "z", adapter: "zcode", skills: ["backend"] } ]
  }' > orchestra.config.json
  . "$ROOT/lib/common.sh"; . "$ROOT/lib/config.sh"; . "$ROOT/lib/adapter.sh"; . "$ROOT/lib/pool.sh"
}

@test "spawn succeeds when zcode answers version" {
  run pool_spawn z
  [ "$status" -eq 0 ]
}

@test "spawn fails when the CLI is broken" {
  export ORCHESTRA_ZCODE_BIN=false
  run pool_spawn z
  [ "$status" -ne 0 ]
}

@test "dispatch runs a headless prompt in the worktree with workflows disabled" {
  printf 'Build the thing.\n' > spec.md
  pool_call z dispatch T1 "$PROJ/spec.md" "$PROJ/work"
  run pool_call z wait T1 10
  [ "$status" -eq 0 ]
  [ "$(cat work/ZCODE_RAN.txt)" = "Build the thing." ]
  grep -qx -- '-p' "$FAKE_ZCODE_LOG"
  grep -qx -- '--workflow-mode' "$FAKE_ZCODE_LOG"
  grep -qx -- 'disabled' "$FAKE_ZCODE_LOG"
  grep -qx -- '--json' "$FAKE_ZCODE_LOG"
}
