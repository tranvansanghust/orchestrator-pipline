#!/usr/bin/env bats
# `orchestra init`: stack detection, scaffolding, never clobbering.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ORCHESTRA="$ROOT/bin/orchestra"
  PROJ="$BATS_TEST_TMPDIR/My_App"
  mkdir -p "$PROJ"
  cd "$PROJ"
}

cfg() { jq -r "$1" orchestra.config.json; }

@test "init scaffolds a typescript project with a valid config" {
  printf '{"scripts":{"build":"tsc"},"devDependencies":{"vitest":"^1.0.0"}}\n' > package.json
  touch tsconfig.json
  run "$ORCHESTRA" init
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f docs/01-SRS.md ]
  [ -f docs/03-adr/0000-template.md ]
  [ -f docs/specs/T0-template.md ]
  [ -f plan.json ]
  [ -f traceability.json ]
  [ -f .claude/commands/plan.md ]
  [ -d .bus ]
  grep -qx '.bus/' .gitignore
  grep -qx '.worktrees/' .gitignore
  [ "$(cfg '.project')" = "my_app" ]
  [ "$(cfg '.orchestra_version')" = "$(cat "$ROOT/VERSION")" ]
  [ "$(cfg '.stack.language')" = "typescript" ]
  [ "$(cfg '.stack.test_one')" = "npx vitest run {files}" ]
  [ "$(cfg '.stack.typecheck')" = "npx tsc --noEmit" ]
  [ "$(cfg '.stack.build')" = "npm run build" ]
  [ "$(cfg '.stack.setup')" = "npm install" ]
  check-jsonschema --schemafile "$ROOT/schemas/config.schema.json" orchestra.config.json
}

@test "init never overwrites; --force does" {
  "$ORCHESTRA" init >/dev/null
  printf 'my PRD\n' > docs/00-PRD.md
  run "$ORCHESTRA" init
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip    docs/00-PRD.md"* ]]
  [ "$(cat docs/00-PRD.md)" = "my PRD" ]
  [ "$(grep -cx '.bus/' .gitignore)" -eq 1 ]
  run "$ORCHESTRA" init --force
  [ "$status" -eq 0 ]
  cmp -s docs/00-PRD.md "$ROOT/templates/docs/00-PRD.md"
}

@test "init detects go, python and rust" {
  touch go.mod
  "$ORCHESTRA" init >/dev/null
  [ "$(cfg '.stack.language')" = "go" ]
  [ "$(cfg '.stack.setup')" = "go mod download" ]
  rm go.mod orchestra.config.json
  touch pyproject.toml
  "$ORCHESTRA" init >/dev/null
  [ "$(cfg '.stack.test_one')" = "pytest {files}" ]
  rm pyproject.toml orchestra.config.json
  touch Cargo.toml
  "$ORCHESTRA" init >/dev/null
  [ "$(cfg '.stack.build')" = "cargo build" ]
}

@test "an unknown stack still yields a schema-valid config" {
  run "$ORCHESTRA" init
  [ "$status" -eq 0 ]
  [ "$(cfg '.stack.language')" = "unknown" ]
  check-jsonschema --schemafile "$ROOT/schemas/config.schema.json" orchestra.config.json
}

@test "init rejects an unknown option" {
  run "$ORCHESTRA" init --yolo
  [ "$status" -eq 2 ]
}

@test "init in a directory of repos sets up a workspace" {
  for r in web svc/api web/sub; do mkdir -p "$r" && git -C "$r" init -q; done
  printf '{"devDependencies":{"jest":"1"}}\n' > web/package.json
  printf 'module x\n' > svc/api/go.mod
  run "$ORCHESTRA" init
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -d .git ]
  ! git rev-parse --verify -q HEAD
  [ "$(cfg '.repos | keys | join(",")')" = "svc-api,web" ]
  [ "$(cfg '.repos["svc-api"].path')" = svc/api ]
  [ "$(cfg '.repos["svc-api"].stack.language')" = go ]
  [ "$(cfg '.repos.web.stack.test_one')" = "npx jest {files}" ]
  [ "$(cfg '.stack.language')" = unknown ]
  grep -qx 'web/' .gitignore
  grep -qx 'svc/api/' .gitignore
  [[ "$output" == *"repo    web/ as web (stack: javascript)"* ]]
  [[ "$output" == *"commit the root repo first"* ]]
  check-jsonschema --schemafile "$ROOT/schemas/config.schema.json" orchestra.config.json
}

@test "init without child repos leaves git alone" {
  run "$ORCHESTRA" init
  [ "$status" -eq 0 ]
  [ ! -d .git ]
  [ "$(cfg '.repos // "none"')" = none ]
}
