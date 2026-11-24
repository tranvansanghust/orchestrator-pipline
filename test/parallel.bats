#!/usr/bin/env bats
# Pool: tasks run in parallel (one per agent), integrate safely, and the
# integration build runs on orchestra/run.
#   T1, T2 independent; T3 depends on both. Two mock agents.

load helpers/project

setup() {
  make_project
  export ORDER="$BATS_TEST_TMPDIR/order.log"
  jq '.agents = [{name: "m1", adapter: "mock", skills: ["backend"]},
                 {name: "m2", adapter: "mock", skills: ["backend"]}]' \
    orchestra.config.json > c && mv c orchestra.config.json
  plan_edit '.tasks += [{id: "T3", desc: "third", deps: ["T1", "T2"], skill: "backend",
    spec_file: "docs/specs/T3.md", areas: [], done_when: {tests_pass: ["t/T3.sh"]}}]
    | .tasks[1].deps = []'
  jq '. + {"FR-3": {desc: "three", tasks: ["T3"], tests: ["t/T3.sh"], acceptance: "a3", status: "planned"}}' \
    traceability.json > t && mv t traceability.json
  printf '\n### FR-3: three\n' >> docs/01-SRS.md
  printf '\n### FR-3\n' >> docs/06-test-plan.md
  printf '# T3\n\nDo the third thing.\n' > docs/specs/T3.md
  git add -A && git -c user.email=t@t -c user.name=t commit -qm three
  # Each agent run logs start/end; T3 insists both earlier tasks reached it.
  export ORCHESTRA_MOCK_CMD='echo "start $1" >> "$ORDER"; sleep 2; mkdir -p t;
    if [ "$1" = T3 ]; then printf "test -f impl-T1.txt && test -f impl-T2.txt\n" > t/T3.sh;
    else printf "exit 0\n" > "t/$1.sh"; fi;
    printf "%s\n" "$1" > "impl-$1.txt"; echo "end $1" >> "$ORDER"'
}

config_edit() {
  jq "$1" orchestra.config.json > c && mv c orchestra.config.json
  git add -A && git -c user.email=t@t -c user.name=t commit -qm cfg
}

@test "two agents run independent tasks at the same time; T3 sees both" {
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; cat "$ORDER"; return 1; }
  [ "$(sed -n 1p "$ORDER" | cut -d' ' -f1)" = start ]
  [ "$(sed -n 2p "$ORDER" | cut -d' ' -f1)" = start ]
  [ "$(tail -1 "$ORDER")" = "end T3" ]
  for t in T1 T2 T3; do [ "$(state "$t")" = DONE ]; done
  [ "$(git show orchestra/run:impl-T3.txt)" = T3 ]
  [[ "$output" == *"up to 2 task(s) at once"* ]]
}

@test "max_parallel 1 runs one task at a time" {
  config_edit '.execution.max_parallel = 1'
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sed -n 2p "$ORDER" | cut -d' ' -f1)" = end ]
}

@test "one agent means one task at a time" {
  config_edit '.agents = [.agents[0]]'
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sed -n 2p "$ORDER" | cut -d' ' -f1)" = end ]
}

@test "a task that conflicts with work merged meanwhile escalates" {
  export ORCHESTRA_MOCK_CMD='sleep 1; mkdir -p t; printf "exit 0\n" > "t/$1.sh"; printf "%s\n" "$1" > shared.txt; printf "%s\n" "$1" > "impl-$1.txt"'
  run "$ORCHESTRA" go
  [ "$status" -eq 4 ]
  n=0
  for t in T1 T2; do
    if [ "$(state "$t")" = ESCALATED ]; then
      n=$((n + 1))
      grep -q 'conflicts with work merged into orchestra/run' ".bus/escalations/$t.md"
    fi
  done
  [ "$n" -eq 1 ]
}

@test "VERIFY is re-run after bringing in work merged meanwhile" {
  # T2 is slow and its test fails once T1's work is present.
  export ORCHESTRA_MOCK_CMD='mkdir -p t;
    if [ "$1" = T2 ]; then sleep 8; printf "test ! -f impl-T1.txt\n" > t/T2.sh;
    else printf "exit 0\n" > "t/$1.sh"; fi; printf "%s\n" "$1" > "impl-$1.txt"'
  run "$ORCHESTRA" go
  [ "$status" -eq 4 ]
  [ "$(state T1)" = DONE ]
  [ "$(state T2)" = ESCALATED ]
  grep -q 'VERIFY fails once the work merged into orchestra/run' .bus/escalations/T2.md
}

@test "the integration build runs on orchestra/run at the end" {
  config_edit '.stack.integration = "test -f impl-T1.txt && test -f impl-T2.txt && test -f impl-T3.txt"'
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"Integration build passed"* ]]
  [ "$(jq -r '.passed' .bus/integration.json)" = true ]
}

@test "a failing integration build needs a human" {
  config_edit '.stack.integration = "echo nope; exit 3"'
  run "$ORCHESTRA" go
  [ "$status" -eq 4 ]
  [[ "$output" == *"Integration build FAILED"* ]]
  grep -q 'nope' .bus/escalations/integration.md
  run "$ORCHESTRA" status
  [[ "$output" == *".bus/escalations/integration.md"* ]]
}

@test "integration off skips the build" {
  config_edit '.stack.integration = "false" | .execution.integration = "off"'
  run "$ORCHESTRA" go
  [ "$status" -eq 0 ]
  [ ! -f .bus/integration.json ]
}
