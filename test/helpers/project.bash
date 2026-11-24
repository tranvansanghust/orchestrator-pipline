# Shared fixture: a tiny two-task git project driven by the mock agent and the
# fake reviewer. Load with `load helpers/project` and call make_project.
#   T1 (no deps)   tests t/T1.sh   FR-1
#   T2 (deps T1)   tests t/T2.sh   FR-2

make_project() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ORCHESTRA="$ROOT/bin/orchestra"
  FAKE="$ROOT/test/fixtures/fake-claude"
  export FAKE_LOG="$BATS_TEST_TMPDIR/calls"
  export SETUP_LOG="$BATS_TEST_TMPDIR/setup.log"
  PROJ="$BATS_TEST_TMPDIR/proj"
  export PROJ
  mkdir -p "$PROJ/docs/specs"
  cd "$PROJ"

  jq -n --arg f "$FAKE -p" --arg pl "$ROOT/test/fixtures/fake-planner" '{
    orchestra_version: "0.1.0", project: "p", profile: "lite",
    stack: { language: "sh", test: "true",
             test_one: "for f in {files}; do sh \"$f\" || exit 1; done",
             setup: "echo ran >> \"$SETUP_LOG\"" },
    brain: { planner: $pl, reviewer: $f, confirmer: $f },
    agents: [ { name: "m", adapter: "mock", skills: ["backend"] } ],
    escalation: { confidence_threshold: 0.75, always_human: ["auth"],
                  max_verify_rounds: 2, max_reject_rounds: 2 },
    execution: { agent_timeout_s: 20 }
  }' > orchestra.config.json
  jq -n '{
    orchestra_version: "0.1.0", goal: "g", approved: false,
    tasks: [
      { id: "T1", desc: "first", deps: [], skill: "backend", spec_file: "docs/specs/T1.md",
        areas: [], done_when: { tests_pass: ["t/T1.sh"] } },
      { id: "T2", desc: "second", deps: ["T1"], skill: "backend", spec_file: "docs/specs/T2.md",
        areas: [], done_when: { tests_pass: ["t/T2.sh"] } }
    ]
  }' > plan.json
  jq -n '{
    "FR-1": { desc: "one", tasks: ["T1"], tests: ["t/T1.sh"], acceptance: "a1", status: "planned" },
    "FR-2": { desc: "two", tasks: ["T2"], tests: ["t/T2.sh"], acceptance: "a2", status: "planned" }
  }' > traceability.json
  printf '# SRS\n\n### FR-1: one\n\n### FR-2: two\n' > docs/01-SRS.md
  printf '# Test plan\n\n### FR-1\n\n### FR-2\n' > docs/06-test-plan.md
  printf '# T1\n\nDo the first thing.\n' > docs/specs/T1.md
  printf '# T2\n\nDo the second thing.\n' > docs/specs/T2.md
  printf '.bus/\n.worktrees/\n' > .gitignore
  git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init

  export ORCHESTRA_MOCK_CMD='mkdir -p t && printf "exit 0\n" > "t/$1.sh" && printf "%s\n" "$1" > "impl-$1.txt"'
  export FAKE_REVIEWER_JSON='{"task":"__TASK__","verdict":"ACCEPT","confidence":0.9,"summary":"ok","evidence":[{"claim":"tests pass","source":"verify_report"}],"needs_human":false}'
  export FAKE_CONFIRMER_JSON='{"task":"__TASK__","upheld":true,"supported":"ACCEPT","reason":"r"}'
}

state() { jq -r '.state' ".bus/tasks/$1.json" 2>/dev/null || echo DRAFT; }
field() { jq -r "$2" ".bus/tasks/$1.json"; }
plan_edit() { jq "$1" plan.json > p && mv p plan.json; }
