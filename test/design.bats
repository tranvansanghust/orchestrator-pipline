#!/usr/bin/env bats
# `orchestra design` and the status dashboard, without tmux.

load helpers/project

setup() {
  make_project
  export FAKE_PLANNER_LOG="$BATS_TEST_TMPDIR/planner.log"
  export ORCHESTRA_NO_TMUX=1
}

@test "design without tmux opens the planner in the project root" {
  run "$ORCHESTRA" design
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"tmux"* ]]
  head -1 "$FAKE_PLANNER_LOG" | grep -q "proj$"
}

@test "status --watch redraws until interrupted (one frame with ORCHESTRA_WATCH_FRAMES)" {
  run env ORCHESTRA_WATCH_FRAMES=2 ORCHESTRA_WATCH_INTERVAL=0 "$ORCHESTRA" status --watch
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^TASK')" -eq 2 ]
}
