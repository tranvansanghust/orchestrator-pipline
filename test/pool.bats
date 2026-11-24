#!/usr/bin/env bats
# Pool + adapter runtime, exercised offline through the mock adapter.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export ORCHESTRA_HOME="$ROOT"
  # An isolated project (not a git repo, so project_root == this dir).
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ"
  cat > "$PROJ/orchestra.config.json" <<'JSON'
{
  "orchestra_version": "0.1.0",
  "project": "t",
  "profile": "standard",
  "stack": { "language": "sh", "test": "true", "test_one": "true {files}" },
  "brain": { "planner": "claude", "reviewer": "claude -p" },
  "agents": [
    { "name": "m1", "adapter": "mock", "skills": ["backend", "api"] },
    { "name": "m2", "adapter": "mock", "skills": ["frontend"] }
  ]
}
JSON
  cd "$PROJ"
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/config.sh"
  . "$ROOT/lib/adapter.sh"
  . "$ROOT/lib/pool.sh"
}

@test "config_get reads a top-level field" {
  [ "$(config_get '.project')" = "t" ]
}

@test "agent_field reads an agent's adapter" {
  [ "$(agent_field m1 '.adapter // empty')" = "mock" ]
}

@test "pool_agents_for_skill matches by skill" {
  [ "$(pool_agents_for_skill backend)" = "m1" ]
  [ "$(pool_agents_for_skill frontend)" = "m2" ]
  [ -z "$(pool_agents_for_skill nonesuch)" ]
}

@test "pool_skills falls back to adapter defaults when config omits skills" {
  # m3 has no skills; mock's capability lists algo.
  jq '.agents += [{"name":"m3","adapter":"mock"}]' orchestra.config.json > c && mv c orchestra.config.json
  run pool_skills m3
  [ "$status" -eq 0 ]
  [[ "$output" == *"algo"* ]]
}

@test "pool_spawn succeeds for the mock adapter" {
  run pool_spawn m1
  [ "$status" -eq 0 ]
}

@test "dispatch + wait: a successful run returns 0 and leaves a log" {
  printf 'do the thing\n' > spec.md
  mkdir work
  pool_call m1 dispatch T1 "$PROJ/spec.md" "$PROJ/work"
  run pool_call m1 wait T1 10
  [ "$status" -eq 0 ]
  [ -f .bus/agents/T1.exit ]
  [[ "$(cat "$(agent_log_path T1)")" == *"T1"* ]]
}

@test "wait reports a failed run as 1" {
  mkdir work
  ORCHESTRA_MOCK_CMD='exit 3' pool_call m1 dispatch T2 "$PROJ/spec.md" "$PROJ/work"
  run pool_call m1 wait T2 10
  [ "$status" -eq 1 ]
}

@test "wait times out as 124" {
  mkdir work
  ORCHESTRA_MOCK_CMD='sleep 5' pool_call m1 dispatch T3 "$PROJ/spec.md" "$PROJ/work"
  run pool_call m1 wait T3 1
  [ "$status" -eq 124 ]
}

@test "timeout terminates the running agent" {
  mkdir work
  ORCHESTRA_MOCK_CMD='sleep 30' pool_call m1 dispatch T5 "$PROJ/spec.md" "$PROJ/work"
  pid=$(cat .bus/agents/T5.pid)
  run pool_call m1 wait T5 1
  [ "$status" -eq 124 ]
  sleep 1
  run kill -0 "$pid"
  [ "$status" -ne 0 ]
}

@test "dispatch runs in the given worktree" {
  mkdir work
  ORCHESTRA_MOCK_CMD='pwd > ran-here.txt' pool_call m1 dispatch T4 "$PROJ/spec.md" "$PROJ/work"
  pool_call m1 wait T4 10
  [ -f work/ran-here.txt ]
}

@test "pool_call on an unknown agent fails" {
  run pool_call ghost spawn
  [ "$status" -ne 0 ]
}
