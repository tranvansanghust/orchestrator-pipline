#!/usr/bin/env bats
# CLI entrypoint: dispatch, exit codes, symlink resolution.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ORCHESTRA="$ROOT/bin/orchestra"
}

@test "help exits 0 and lists every command" {
  run "$ORCHESTRA" help
  [ "$status" -eq 0 ]
  for c in init design go status resolve stop version; do
    [[ "$output" == *"$c"* ]]
  done
}

@test "no arguments prints help" {
  run "$ORCHESTRA"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: orchestra"* ]]
}

@test "version matches the VERSION file" {
  run "$ORCHESTRA" version
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$ROOT/VERSION")" ]
}

@test "unknown command exits 2" {
  run "$ORCHESTRA" bogus
  [ "$status" -eq 2 ]
}

@test "resolve without a task is a usage error" {
  # Every command is implemented and has its own test file. Commands that act
  # on a project (init, go, design, stop, ...) are never run here: they would
  # write into the orchestra repo itself.
  run "$ORCHESTRA" resolve
  [ "$status" -eq 2 ]
}

@test "works when invoked through a symlink" {
  ln -s "$ORCHESTRA" "$BATS_TEST_TMPDIR/orchestra"
  run "$BATS_TEST_TMPDIR/orchestra" version
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$ROOT/VERSION")" ]
}
