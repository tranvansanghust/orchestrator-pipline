# shellcheck shell=sh
# Git layout of a run (ADR-0010):
#   orchestra/run         integration branch, created from HEAD by `go`, with
#                         the frozen design committed on top; checked out in
#                         .worktrees/_run. The user's own branch is never touched.
#   orchestra/<task-id>   one branch + worktree (.worktrees/<task-id>) per task,
#                         from the tip of orchestra/run; merged back --no-ff
#                         after ACCEPT.
# The commit a task starts from is recorded as `base` in .bus/tasks/<id>.json.

_WT_RUN=orchestra/run

_wt_dir() { printf '%s/.worktrees/%s\n' "$(project_root)" "$1"; }

# _wt_git <git-args...> — git, with a fallback identity when none is set.
_wt_git() {
  if git config user.email >/dev/null 2>&1; then
    git "$@"
  else
    git -c user.name=orchestra -c user.email=orchestra@localhost "$@"
  fi
}

# worktree_run_init — make sure orchestra/run exists, is checked out in
# .worktrees/_run, and carries the frozen design as its latest commit.
worktree_run_init() {
  _root=$(project_root)
  git -C "$_root" rev-parse --verify -q HEAD >/dev/null 2>&1 \
    || die "orchestra go needs a git repository with at least one commit"
  _run=$(_wt_dir _run)
  if [ ! -d "$_run" ]; then
    if git -C "$_root" show-ref --verify -q "refs/heads/$_WT_RUN"; then
      git -C "$_root" worktree add "$_run" "$_WT_RUN" >/dev/null 2>&1
    else
      git -C "$_root" worktree add -b "$_WT_RUN" "$_run" HEAD >/dev/null 2>&1
    fi || die "could not create the $_WT_RUN worktree in .worktrees/_run"
  fi
  for _p in docs plan.json traceability.json orchestra.config.json; do
    [ -e "$_root/$_p" ] || continue
    rm -rf "${_run:?}/$_p"
    cp -R "$_root/$_p" "$_run/$_p"
  done
  _wt_git -C "$_run" add -A -- docs plan.json traceability.json orchestra.config.json >/dev/null 2>&1 || true
  if ! git -C "$_run" diff --cached --quiet; then
    _wt_git -C "$_run" commit -q -m "orchestra: frozen design ($(jq -r '.frozen_at' "$(bus_dir)/frozen.json"))"
  fi
}

# worktree_base <task-id> — the commit the task's worktree started from.
worktree_base() {
  _wf=$(bus_dir)/tasks/$1.json
  [ -f "$_wf" ] || die "no task state for $1 (.bus/tasks/$1.json): base commit unknown"
  _wb=$(jq -r '.base // empty' "$_wf")
  [ -n "$_wb" ] || die "task $1 has no base commit in .bus/tasks/$1.json"
  printf '%s\n' "$_wb"
}

# worktree_create <task-id> — branch orchestra/<task-id> from the tip of
# orchestra/run, check it out in .worktrees/<task-id>, record base/branch/path.
worktree_create() {
  _root=$(project_root)
  _wt=$(_wt_dir "$1")
  _br=orchestra/$1
  bus_lock git
  if git -C "$_root" show-ref --verify -q "refs/heads/$_br"; then
    git -C "$_root" worktree add "$_wt" "$_br" >/dev/null 2>&1 || { bus_unlock git; return 1; }
  else
    git -C "$_root" worktree add -b "$_br" "$_wt" "$_WT_RUN" >/dev/null 2>&1 || { bus_unlock git; return 1; }
  fi
  _base=$(git -C "$_root" merge-base "$_WT_RUN" "$_br")
  bus_unlock git
  # shellcheck disable=SC2016 # jq variables
  task_update "$1" '.base = $b | .branch = $br | .worktree = $w' \
    --arg b "$_base" --arg br "$_br" --arg w "$_wt"
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

# worktree_commit <task-id> <message> — commit whatever the agent left
# uncommitted in the task worktree.
worktree_commit() {
  _wt=$(_wt_dir "$1")
  _wt_git -C "$_wt" add -A >/dev/null 2>&1 || return 1
  if ! git -C "$_wt" diff --cached --quiet; then
    _wt_git -C "$_wt" commit -q -m "$2" || return 1
  fi
}

# worktree_update <task-id> — merge what reached orchestra/run since the task
# branched into the task branch. On conflict the merge is aborted and 1 is
# returned. Caller holds the git lock.
worktree_update() {
  _wt=$(_wt_dir "$1")
  if ! _wt_git -C "$_wt" merge -q --no-edit "$_WT_RUN" >/dev/null 2>&1; then
    git -C "$_wt" merge --abort >/dev/null 2>&1 || true
    return 1
  fi
}

# worktree_merge <task-id> — merge orchestra/<task-id> into orchestra/run.
# On conflict the merge is aborted and 1 is returned. Caller holds the git
# lock (or no run is active).
worktree_merge() {
  _run=$(_wt_dir _run)
  if ! _wt_git -C "$_run" merge -q --no-ff -m "orchestra: merge $1 — $(plan_task "$1" '.desc')" "orchestra/$1" >/dev/null 2>&1; then
    git -C "$_run" merge --abort >/dev/null 2>&1 || true
    return 1
  fi
}

# worktree_remove <task-id> — drop the task worktree; the branch is kept.
worktree_remove() {
  bus_lock git
  git -C "$(project_root)" worktree remove --force "$(_wt_dir "$1")" >/dev/null 2>&1 || true
  bus_unlock git
}
