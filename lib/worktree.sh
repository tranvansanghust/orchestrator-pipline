# shellcheck shell=sh
# One git worktree per task (.worktrees/<task-id>), so agents never step on
# each other and verify runs isolated. Merge only after ACCEPT.

# worktree_create <task-id> — create branch orchestra/<task-id> + worktree.
worktree_create() { not_implemented worktree_create; }

# worktree_diff <task-id> — print the task's diff against its base.
worktree_diff() { not_implemented worktree_diff; }

# worktree_merge <task-id> — merge the accepted task branch.
worktree_merge() { not_implemented worktree_merge; }

# worktree_remove <task-id> — drop the worktree after merge or abandon.
worktree_remove() { not_implemented worktree_remove; }
