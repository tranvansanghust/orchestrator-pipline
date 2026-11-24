#!/usr/bin/env bats
# Every adapter must implement the four-function interface (adapters/README.md).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "every adapter defines the four interface functions under POSIX sh" {
  for f in "$ROOT"/adapters/*.sh; do
    run sh -c '
      . "$1"
      for fn in adapter_spawn adapter_dispatch adapter_wait adapter_capability; do
        command -v "$fn" >/dev/null || { echo "$1: missing $fn"; exit 1; }
      done
    ' _ "$f"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  done
}
