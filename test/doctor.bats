#!/usr/bin/env bats
# `orchestra doctor` and config validation.

load helpers/project

setup() {
  make_project
  # A stub claude so the machine checks pass regardless of where tests run.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "doctor passes in a healthy project and lists the agents" {
  run "$ORCHESTRA" doctor
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"ok    orchestra.config.json is valid"* ]]
  [[ "$output" == *"agent m (mock) is available"* ]]
  [[ "$output" == *"plan.json not approved yet"* ]]
}

@test "doctor outside a project only checks the machine" {
  mkdir "$BATS_TEST_TMPDIR/empty"
  cd "$BATS_TEST_TMPDIR/empty"
  run "$ORCHESTRA" doctor
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"Not inside an orchestra project"* ]]
}

@test "doctor fails on an invalid config" {
  jq '.profile = "yolo"' orchestra.config.json > c && mv c orchestra.config.json
  run "$ORCHESTRA" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL  orchestra.config.json"* ]]
}

@test "doctor fails when an agent's CLI is missing" {
  jq '.agents += [{name: "z", adapter: "zcode", skills: ["x"]}]' orchestra.config.json > c && mv c orchestra.config.json
  run env ORCHESTRA_ZCODE_BIN=false ZCODE_APP=/nonexistent "$ORCHESTRA" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"agent z (zcode): its CLI is not available"* ]]
}

@test "a major version mismatch warns" {
  jq '.orchestra_version = "9.0.0"' orchestra.config.json > c && mv c orchestra.config.json
  run "$ORCHESTRA" doctor
  [[ "$output" == *"pinned to orchestra 9.0.0"* ]]
}

@test "go refuses an invalid config before doing anything" {
  jq 'del(.stack.test_one)' orchestra.config.json > c && mv c orchestra.config.json
  run "$ORCHESTRA" go
  [ "$status" -ne 0 ]
  [[ "$output" == *"schemas/config.schema.json"* ]]
  [ "$(jq -r '.approved' plan.json)" = false ]
}
