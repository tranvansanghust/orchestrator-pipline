#!/usr/bin/env bats
# Online smoke tests for the real adapters. Skipped unless ORCHESTRA_ONLINE=1,
# so CI stays free and deterministic. These spend real API calls.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export ORCHESTRA_HOME="$ROOT"
  [ "${ORCHESTRA_ONLINE:-}" = "1" ] || skip "set ORCHESTRA_ONLINE=1 to run (spends API calls)"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/work"
  cd "$PROJ"
  . "$ROOT/lib/common.sh"; . "$ROOT/lib/config.sh"; . "$ROOT/lib/adapter.sh"; . "$ROOT/lib/pool.sh"
}

write_config() {
  cat > "$PROJ/orchestra.config.json" <<JSON
{
  "orchestra_version": "0.1.0", "project": "t", "profile": "standard",
  "stack": { "language": "sh", "test": "true", "test_one": "true {files}" },
  "brain": { "planner": "claude", "reviewer": "claude -p" },
  "agents": [ { "name": "a", "adapter": "$1"${2:+, \"model\": \"$2\"} } ]
}
JSON
}

@test "opencode: spawn verifies the CLI" {
  command -v opencode >/dev/null || skip "opencode not installed"
  write_config opencode
  run pool_spawn a
  [ "$status" -eq 0 ]
}

@test "opencode: writes a file into the worktree" {
  command -v opencode >/dev/null || skip "opencode not installed"
  write_config opencode
  printf 'Create a file named HELLO.txt containing the word orchestra. Then stop.\n' > spec.md
  pool_call a dispatch T1 "$PROJ/spec.md" "$PROJ/work"
  run pool_call a wait T1 180
  [ "$status" -eq 0 ]
  [ -f work/HELLO.txt ]
}

@test "claude: spawn verifies the CLI" {
  command -v claude >/dev/null || skip "claude not installed"
  write_config claude
  run pool_spawn a
  [ "$status" -eq 0 ]
}

@test "claude: writes a file into the worktree" {
  command -v claude >/dev/null || skip "claude not installed"
  write_config claude
  printf 'Create a file named HELLO.txt containing the word orchestra. Then stop.\n' > spec.md
  pool_call a dispatch T1 "$PROJ/spec.md" "$PROJ/work"
  run pool_call a wait T1 180
  [ "$status" -eq 0 ]
  [ -f work/HELLO.txt ]
}
