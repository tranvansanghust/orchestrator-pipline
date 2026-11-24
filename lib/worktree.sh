# shellcheck shell=sh
# One git worktree per task (.worktrees/<task-id>), so agents never step on
# each other and verify runs isolated. Merge only after ACCEPT.
# The commit a task starts from is recorded as `base` in .bus/tasks/<id>.json.

# worktree_base <task-id> — the commit the task's worktree started from.
worktree_base() {
  _wf=$(bus_dir)/tasks/$1.json
  [ -f "$_wf" ] || die "no task state for $1 (.bus/tasks/$1.json): base commit unknown"
  _wb=$(jq -r '.base // empty' "$_wf")
  [ -n "$_wb" ] || die "task $1 has no base commit in .bus/tasks/$1.json"
  printf '%s\n' "$_wb"
}

# Make untracked files visible to `git diff` without staging their content.
_wt_intent() {
  git -C "$1" add -N -- . ':(exclude).bus' ':(exclude).worktrees' >/dev/null 2>&1 || true
}

# worktree_diff <task-id> <worktree> — everything the task changed since its
# base: commits, uncommitted edits and new files.
worktree_diff() {
  _wb=$(worktree_base "$1")
  _wt_intent "$2"
  git -C "$2" diff "$_wb" -- . ':(exclude).bus' ':(exclude).worktrees'
}

# worktree_changed_files <task-id> <worktree> — paths changed since base.
worktree_changed_files() {
  _wb=$(worktree_base "$1")
  _wt_intent "$2"
  git -C "$2" diff --name-only "$_wb" -- . ':(exclude).bus' ':(exclude).worktrees'
}

# worktree_create <task-id> — create branch orchestra/<task-id> + worktree and
# record its base (roadmap step 4).
worktree_create() { not_implemented worktree_create; }

# worktree_merge <task-id> — merge the accepted task branch (roadmap step 4).
worktree_merge() { not_implemented worktree_merge; }

# worktree_remove <task-id> — drop the worktree after merge or abandon.
worktree_remove() { not_implemented worktree_remove; }
