#!/usr/bin/env bats
# `orchestra go`: readiness gate, plan approval, freeze manifest.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ORCHESTRA="$ROOT/bin/orchestra"
  PROJ="$BATS_TEST_TMPDIR/proj"
  cp -R "$ROOT/examples/blog-api" "$PROJ"
  cd "$PROJ"
}

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

@test "go approves a ready plan and freezes the artifacts" {
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(jq -r '.approved' plan.json)" = "true" ]
  [ -f .bus/frozen.json ]
  [ "$(jq -r '.profile' .bus/frozen.json)" = "standard" ]
  [ "$(jq -r '.files["docs/01-SRS.md"]' .bus/frozen.json)" = "$(sha docs/01-SRS.md)" ]
  [ "$(jq -r '.files["plan.json"]' .bus/frozen.json)" = "$(sha plan.json)" ]
  [ "$(jq -r '.files["docs/specs/T3.md"]' .bus/frozen.json)" = "$(sha docs/specs/T3.md)" ]
}

@test "go --profile overrides the config profile" {
  run "$ORCHESTRA" go --profile lite
  [ "$status" -eq 0 ]
  [ "$(jq -r '.profile' .bus/frozen.json)" = "lite" ]
}

@test "go refuses a plan that is not ready and leaves it unapproved" {
  rm docs/specs/T5.md
  run "$ORCHESTRA" go
  [ "$status" -ne 0 ]
  [[ "$output" == *"readiness check failed"* ]]
  [ "$(jq -r '.approved' plan.json)" = "false" ]
  [ ! -f .bus/frozen.json ]
}

@test "go rejects an unknown option" {
  run "$ORCHESTRA" go --yolo
  [ "$status" -eq 2 ]
}
