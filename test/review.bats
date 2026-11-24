#!/usr/bin/env bats
# Review layer, offline: a fake claude returns canned verdicts.
# The project is a git copy of examples/blog-api; task T5 (no sensitive area,
# scope src/routes/posts.ts) and T3 (area auth) are reviewed.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export ORCHESTRA_HOME="$ROOT"
  export FAKE_LOG="$BATS_TEST_TMPDIR/calls"
  PROJ="$BATS_TEST_TMPDIR/proj"
  cp -R "$ROOT/examples/blog-api" "$PROJ"
  cd "$PROJ"
  FAKE="$ROOT/test/fixtures/fake-claude"
  jq --arg f "$FAKE -p" \
    '.brain.reviewer = $f | .brain.confirmer = {cmd: $f, model: "claude-haiku-4-5-20251001"}' \
    orchestra.config.json > c && mv c orchestra.config.json
  printf '.bus/\n' > .gitignore
  git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm base
  BASE=$(git rev-parse HEAD)
  mkdir -p .bus/tasks .bus/verify src/routes test
  for t in T3 T5; do
    printf '{"base":"%s"}\n' "$BASE" > ".bus/tasks/$t.json"
    printf '{"task":"%s","passed":true,"checks":[],"verified_at":"now"}\n' "$t" > ".bus/verify/$t.json"
  done
  # The agent's change for T5: in-scope route + its test.
  printf 'export const listPosts = () => [];\n' > src/routes/posts.ts
  printf 'test("lists newest first", () => {});\n' > test/posts.list.test.ts
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/config.sh"
  . "$ROOT/lib/worktree.sh"
  . "$ROOT/lib/review.sh"
}

verdict() { # <task> <verdict> [confidence] [extra-jq]
  jq -nc --arg t "$1" --arg v "$2" --argjson c "${3:-0.9}" "{
    task: \$t, verdict: \$v, confidence: \$c, summary: \"s\",
    evidence: [{claim: \"tests pass\", source: \"verify_report\"}], needs_human: false
  } ${4:-}"
}
confirm() { jq -nc --arg t "$1" --argjson u "$2" --arg s "$3" '{task: $t, upheld: $u, supported: $s, reason: "r"}'; }
decision() { jq -r "$1" "$PROJ/.bus/review/$2/round-${3:-1}/decision.json"; }
calls() { ls "$FAKE_LOG" 2>/dev/null | grep -c "^$1-.*\.prompt$" || true; }

@test "ACCEPT upheld by the confirmer stays ACCEPT; decision is schema-valid" {
  export FAKE_REVIEWER_JSON=$(verdict T5 ACCEPT)
  export FAKE_CONFIRMER_JSON=$(confirm T5 true ACCEPT)
  run review_run T5 "$PROJ"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "ACCEPT" ]
  [ "$(decision '.upheld' T5)" = "true" ]
  [ "$(decision '.synthetic_verdict' T5)" = "false" ]
  [ "$(decision '.cost_usd' T5)" = "0.04" ]
  check-jsonschema --schemafile "$ROOT/schemas/decision.schema.json" .bus/review/T5/round-1/decision.json
}

@test "reviewer runs without tools, with the verdict schema, pack on stdin" {
  export FAKE_REVIEWER_JSON=$(verdict T5 ACCEPT)
  export FAKE_CONFIRMER_JSON=$(confirm T5 true ACCEPT)
  review_run T5 "$PROJ"
  args="$FAKE_LOG/reviewer-1.args"
  grep -qx -- '--tools' "$args"
  grep -qx -- '--json-schema' "$args"
  grep -q '"fixes_requested"' "$args"
  grep -qx -- '--system-prompt' "$args"
  ! grep -q '"allOf"' "$args"
  prompt="$FAKE_LOG/reviewer-1.prompt"
  grep -q '^## Task T5' "$prompt"
  grep -q '^## Verify report' "$prompt"
  grep -q 'export const listPosts' "$prompt"
  grep -Eq '^<untrusted-data id="[0-9a-f]{16}" source="diff">' "$prompt"
  grep -q 'source="test:test/posts.list.test.ts"' "$prompt"
}

@test "the confirmer gets its pinned model; the reviewer does not" {
  export FAKE_REVIEWER_JSON=$(verdict T5 ACCEPT)
  export FAKE_CONFIRMER_JSON=$(confirm T5 true ACCEPT)
  review_run T5 "$PROJ"
  grep -qx 'claude-haiku-4-5-20251001' "$FAKE_LOG/confirmer-1.args"
  ! grep -qx -- '--model' "$FAKE_LOG/reviewer-1.args"
}

@test "ACCEPT not upheld drops to the confirmer's supported verdict" {
  export FAKE_REVIEWER_JSON=$(verdict T5 ACCEPT)
  export FAKE_CONFIRMER_JSON=$(confirm T5 false REJECT)
  run review_run T5 "$PROJ"
  [ "$output" = "REJECT" ]
  [[ "$(decision '.reasons[0]' T5)" == "confirmer did not uphold ACCEPT"* ]]
}

@test "a not-upheld ACCEPT can never stay ACCEPT" {
  export FAKE_REVIEWER_JSON=$(verdict T5 ACCEPT)
  export FAKE_CONFIRMER_JSON=$(confirm T5 false ACCEPT)
  run review_run T5 "$PROJ"
  [ "$output" = "ESCALATE" ]
}

@test "REJECT skips the confirmer; round 2 sees the requested fixes" {
  export FAKE_REVIEWER_JSON=$(verdict T5 REJECT 0.9 '+ {fixes_requested: ["add the id tie-break"]}')
  run review_run T5 "$PROJ"
  [ "$output" = "REJECT" ]
  [ "$(calls confirmer)" -eq 0 ]
  [ "$(decision '.upheld' T5)" = "null" ]
  run review_run T5 "$PROJ"
  [ -f .bus/review/T5/round-2/decision.json ]
  grep -q 'add the id tie-break' "$FAKE_LOG/reviewer-2.prompt"
}

@test "invalid reviewer output is retried once with the error" {
  export FAKE_INVALID=1
  export FAKE_REVIEWER_JSON=$(verdict T5 ACCEPT)
  export FAKE_CONFIRMER_JSON=$(confirm T5 true ACCEPT)
  run review_run T5 "$PROJ"
  [ "$output" = "ACCEPT" ]
  [ "$(calls reviewer)" -eq 2 ]
  grep -q 'Your previous reply was rejected' "$FAKE_LOG/reviewer-2.prompt"
}

@test "reviewer output invalid twice becomes a synthetic ESCALATE" {
  export FAKE_INVALID=9
  export FAKE_REVIEWER_JSON=$(verdict T5 ACCEPT)
  run review_run T5 "$PROJ"
  [ "$output" = "ESCALATE" ]
  [ "$(decision '.synthetic_verdict' T5)" = "true" ]
  [ "$(calls confirmer)" -eq 0 ]
}

@test "a verdict for the wrong task is rejected as invalid" {
  export FAKE_REVIEWER_JSON=$(verdict T4 ACCEPT)
  run review_run T5 "$PROJ"
  [ "$output" = "ESCALATE" ]
  grep -q 'expected T5' .bus/review/T5/round-1/verdict-error-1.txt
}

@test "hard rule: low confidence escalates" {
  export FAKE_REVIEWER_JSON=$(verdict T5 REJECT 0.5 '+ {fixes_requested: ["x"]}')
  run review_run T5 "$PROJ"
  [ "$output" = "ESCALATE" ]
  [[ "$(decision '.reasons[0]' T5)" == *"below the threshold 0.75"* ]]
}

@test "hard rule: a high concern escalates" {
  export FAKE_REVIEWER_JSON=$(verdict T5 ACCEPT 0.9 '+ {concerns: [{severity: "high", detail: "d"}]}')
  export FAKE_CONFIRMER_JSON=$(confirm T5 true ACCEPT)
  run review_run T5 "$PROJ"
  [ "$output" = "ESCALATE" ]
  [[ "$(decision '.reasons | join(" ")' T5)" == *"1 high/critical concern"* ]]
}

@test "hard rule: an always_human area escalates an ACCEPT" {
  export FAKE_REVIEWER_JSON=$(verdict T3 ACCEPT)
  export FAKE_CONFIRMER_JSON=$(confirm T3 true ACCEPT)
  run review_run T3 "$PROJ"
  [ "$output" = "ESCALATE" ]
  [[ "$(decision '.reasons | join(" ")' T3)" == *'task area "auth" is always_human'* ]]
}

@test "hard rule: a file outside the task scope escalates" {
  printf 'x\n' > src/other.ts
  export FAKE_REVIEWER_JSON=$(verdict T5 ACCEPT)
  export FAKE_CONFIRMER_JSON=$(confirm T5 true ACCEPT)
  run review_run T5 "$PROJ"
  [ "$output" = "ESCALATE" ]
  [[ "$(decision '.reasons | join(" ")' T5)" == *"src/other.ts is outside the task scope"* ]]
}

@test "an oversize pack escalates without calling the reviewer" {
  jq '.review = {max_pack_bytes: 1000}' orchestra.config.json > c && mv c orchestra.config.json
  head -c 5000 /dev/zero | tr '\0' 'a' > src/routes/posts.ts
  run review_run T5 "$PROJ"
  [ "$output" = "ESCALATE" ]
  [ "$(calls reviewer)" -eq 0 ]
  [ "$(decision '.synthetic_verdict' T5)" = "true" ]
  [ "$(decision '.dropped_sections | join(",")' T5)" = "conventions,contracts,architecture,brief" ]
}

@test "review refuses to run before VERIFY is green" {
  printf '{"task":"T5","passed":false,"checks":[],"verified_at":"now"}\n' > .bus/verify/T5.json
  run review_run T5 "$PROJ"
  [ "$status" -ne 0 ]
  [[ "$output" == *"VERIFY is not green"* ]]
}
