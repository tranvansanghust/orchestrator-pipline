#!/usr/bin/env bats
# Multi-repo worktrees (ADR-0013): root plus child repo web/. T1 may change
# root and web; T2 only root, so its web/ is a detached, read-only checkout.

load helpers/project

setup() {
  make_workspace
  export ORCHESTRA_HOME="$ROOT"
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/config.sh"
  . "$ROOT/lib/bus.sh"
  . "$ROOT/lib/statemachine.sh"
  . "$ROOT/lib/worktree.sh"
  plan_edit '.tasks[0].repos = ["root", "web"]'
  bus_init
  printf '{"frozen_at":"now"}\n' > .bus/frozen.json
  worktree_run_init
}

head_of() { git -C "$1" rev-parse HEAD; }
branch_of() { git -C "$1" rev-parse --abbrev-ref HEAD; }

@test "go creates orchestra/run in every repo, nested like the workspace" {
  [ "$(branch_of .worktrees/_run)" = orchestra/run ]
  [ "$(branch_of .worktrees/_run/web)" = orchestra/run ]
  [ "$(branch_of .)" != orchestra/run ]
  [ "$(branch_of web)" != orchestra/run ]
  [ "$(git show orchestra/run:plan.json | jq -r '.tasks[0].repos[1]')" = web ]
}

@test "a task gets a branch in its repos and a detached checkout of the others" {
  run worktree_create T1
  [ "$status" -eq 0 ]
  [ "$output" = "root
web" ]
  [ "$(branch_of .worktrees/T1/web)" = orchestra/T1 ]
  run worktree_create T2
  [ "$output" = root ]
  [ "$(branch_of .worktrees/T2)" = orchestra/T2 ]
  [ "$(branch_of .worktrees/T2/web)" = HEAD ]
  [ "$(cat .worktrees/T2/web/app.txt)" = v1 ]
  ! git -C web show-ref --verify -q refs/heads/orchestra/T2
  [ "$(jq -r '.bases | keys | join(",")' .bus/tasks/T2.json)" = root,web ]
  [ "$(jq -r '.base' .bus/tasks/T2.json)" = "$(jq -r '.bases.root' .bus/tasks/T2.json)" ]
  # Idempotent: nothing new to check out.
  run worktree_create T1
  [ -z "$output" ]
}

@test "diff and changed files cover every repo with project-relative paths" {
  worktree_create T1 >/dev/null
  printf 'v2\n' > .worktrees/T1/web/app.txt
  printf 'x\n' > .worktrees/T1/new.txt
  run worktree_changed_files T1 "$PWD/.worktrees/T1"
  [ "$output" = "new.txt
web/app.txt" ]
  run worktree_diff T1 "$PWD/.worktrees/T1"
  [[ "$output" == *"+++ b/web/app.txt"* ]]
  [[ "$output" == *"+++ b/new.txt"* ]]
  [[ "$output" != *".bus"* ]]
}

@test "changes in a repo the task may not change are found and discarded" {
  worktree_create T2 >/dev/null
  printf 'hacked\n' > .worktrees/T2/web/app.txt
  printf 'n\n' > .worktrees/T2/web/extra.txt
  printf 'ok\n' > .worktrees/T2/mine.txt
  run worktree_foreign T2
  [ "$output" = "web web/app.txt
web web/extra.txt" ]
  worktree_foreign_discard T2
  [ -z "$(worktree_foreign T2)" ]
  [ "$(cat .worktrees/T2/web/app.txt)" = v1 ]
  [ ! -e .worktrees/T2/web/extra.txt ]
  [ -f .worktrees/T2/mine.txt ]
}

@test "root is foreign to a task that only names other repos, commits included" {
  plan_edit '.tasks[0].repos = ["web"]'
  worktree_create T1 >/dev/null
  printf 'x\n' > .worktrees/T1/stray.txt
  git -C .worktrees/T1 add stray.txt && git -C .worktrees/T1 -c user.email=t@t -c user.name=t commit -qm stray
  printf 'v2\n' > .worktrees/T1/web/app.txt
  run worktree_foreign T1
  [ "$output" = "root stray.txt" ]
  worktree_foreign_discard T1
  [ -z "$(worktree_foreign T1)" ]
  [ "$(cat .worktrees/T1/web/app.txt)" = v2 ]
}

@test "commit, update and merge move every repo of the task" {
  worktree_create T1 >/dev/null
  printf 'v2\n' > .worktrees/T1/web/app.txt
  printf 'r\n' > .worktrees/T1/impl.txt
  worktree_commit T1 "T1 work"
  worktree_update T1
  worktree_merge T1
  [ "$(git -C web show orchestra/run:app.txt)" = v2 ]
  [ "$(git show orchestra/run:impl.txt)" = r ]
  [ "$(git -C web log orchestra/run --merges --format=%s)" = "orchestra: merge T1 — first" ]
  [ "$(cat web/app.txt)" = v1 ]
}

@test "a conflict in one repo rolls back the update in all of them" {
  plan_edit '.tasks[1].repos = ["root", "web"]'
  worktree_create T1 >/dev/null
  worktree_create T2 >/dev/null
  printf 'a\n' > .worktrees/T1/web/app.txt
  printf 'r1\n' > .worktrees/T1/impl-T1.txt
  printf 'b\n' > .worktrees/T2/web/app.txt
  worktree_commit T1 "T1"
  worktree_commit T2 "T2"
  worktree_update T1 && worktree_merge T1
  before=$(worktree_heads T2)
  run worktree_update T2
  [ "$status" -eq 1 ]
  [ "$(worktree_heads T2)" = "$before" ]
  [ ! -e .worktrees/T2/impl-T1.txt ]
  [ -z "$(git -C .worktrees/T2/web status --porcelain)" ]
}

@test "a failing merge leaves orchestra/run untouched in every repo" {
  worktree_create T1 >/dev/null
  printf 'v2\n' > .worktrees/T1/web/app.txt
  printf 'r\n' > .worktrees/T1/impl.txt
  worktree_commit T1 "T1"
  printf 'dirty\n' > .worktrees/_run/web/app.txt
  before=$(worktree_heads _run)
  run worktree_merge T1
  [ "$status" -eq 1 ]
  [ "$(worktree_heads _run)" = "$before" ]
  ! git show orchestra/run:impl.txt 2>/dev/null
}

@test "remove drops every checkout; drop_branches deletes the branches everywhere" {
  worktree_create T1 >/dev/null
  worktree_create T2 >/dev/null
  worktree_remove T1
  worktree_remove T2
  [ ! -e .worktrees/T1 ] && [ ! -e .worktrees/T2 ]
  [ -z "$(git -C web worktree list | grep -E 'T1|T2')" ]
  git -C web show-ref --verify -q refs/heads/orchestra/T1
  worktree_drop_branches T1
  ! git -C web show-ref --verify -q refs/heads/orchestra/T1
  ! git show-ref --verify -q refs/heads/orchestra/T1
}
