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

@test "unimplemented commands exit 3" {
  # init and go are implemented (test/init.bats, test/go.bats); never run init
  # here, it would scaffold into the orchestra repo itself.
  for c in design status resolve stop; do
    run "$ORCHESTRA" "$c"
    [ "$status" -eq 3 ]
  done
}

@test "works when invoked through a symlink" {
  ln -s "$ORCHESTRA" "$BATS_TEST_TMPDIR/orchestra"
  run "$BATS_TEST_TMPDIR/orchestra" version
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$ROOT/VERSION")" ]
}
