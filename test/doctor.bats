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

# add_repo <name> — a child git repo under the project, in the config.
add_repo() {
  mkdir "$1" && git -C "$1" init -q && touch "$1/f"
  git -C "$1" add -A && git -C "$1" -c user.email=t@t -c user.name=t commit -qm init
  jq --arg n "$1" '.repos[$n] = {path: $n, stack: .stack}' orchestra.config.json > c && mv c orchestra.config.json
}

@test "doctor accepts a workspace whose repos are gitignored git repos" {
  add_repo web
  printf 'web/\n' >> .gitignore
  run "$ORCHESTRA" doctor
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "doctor fails a repo the root does not ignore" {
  add_repo web
  run "$ORCHESTRA" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"repos.web: add web/ to the root .gitignore"* ]]
}

@test "doctor fails a repo path that is not a git repository" {
  mkdir web
  printf 'web/\n' >> .gitignore
  jq '.repos.web = {path: "web", stack: .stack}' orchestra.config.json > c && mv c orchestra.config.json
  run "$ORCHESTRA" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"repos.web: web is not the top of a git repository"* ]]
}

@test "doctor fails nested repos" {
  add_repo web
  mkdir -p web/sub && git -C web/sub init -q
  jq '.repos.sub = {path: "web/sub", stack: .stack}' orchestra.config.json > c && mv c orchestra.config.json
  printf 'web/\n' >> .gitignore
  run "$ORCHESTRA" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"repos.sub (web/sub) is inside repos.web"* ]]
}
