#!/usr/bin/env bats
# Online review with the real claude CLI. Skipped unless ORCHESTRA_ONLINE=1;
# spends real API calls (capped by review.max_budget_usd).

setup() {
  [ "${ORCHESTRA_ONLINE:-}" = "1" ] || skip "set ORCHESTRA_ONLINE=1 to run (spends API calls)"
  command -v claude >/dev/null || skip "claude not installed"
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export ORCHESTRA_HOME="$ROOT"
  PROJ="$BATS_TEST_TMPDIR/proj"
  cp -R "$ROOT/examples/blog-api" "$PROJ"
  cd "$PROJ"
  jq '.review = {max_budget_usd: 0.5}' orchestra.config.json > c && mv c orchestra.config.json
  printf '.bus/\n' > .gitignore
  git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm base
  mkdir -p .bus/tasks .bus/verify src/routes test
  printf '{"base":"%s"}\n' "$(git rev-parse HEAD)" > .bus/tasks/T5.json
  printf '{"task":"T5","passed":true,"checks":[{"name":"tests","cmd":"npx vitest run test/posts.list.test.ts","exit":0,"passed":true}],"verified_at":"now"}\n' \
    > .bus/verify/T5.json
  # Deliberately buggy: orders by created_at only (the review brief's known risk).
  cat > src/routes/posts.ts <<'TS'
import { Router } from "express";
import { db } from "../db";
export const posts = Router();
posts.get("/posts", async (req, res) => {
  const limit = Math.min(Number(req.query.limit ?? 20), 50);
  const rows = await db.query("SELECT * FROM posts ORDER BY created_at DESC LIMIT $1", [limit]);
  res.json({ items: rows, next_cursor: null });
});
TS
  printf 'test("lists posts", async () => { expect(true).toBe(true); });\n' > test/posts.list.test.ts
  . "$ROOT/lib/common.sh"; . "$ROOT/lib/config.sh"; . "$ROOT/lib/worktree.sh"; . "$ROOT/lib/review.sh"
}

@test "real reviewer returns a valid, non-synthetic decision and does not ACCEPT a buggy change" {
  run review_run T5 "$PROJ"
  echo "verdict: $output"
  cat .bus/review/T5/round-1/decision.json
  [ "$status" -eq 0 ]
  check-jsonschema --schemafile "$ROOT/schemas/decision.schema.json" .bus/review/T5/round-1/decision.json
  [ "$(jq -r '.synthetic_verdict' .bus/review/T5/round-1/decision.json)" = "false" ]
  [ "$output" != "ACCEPT" ]
}
