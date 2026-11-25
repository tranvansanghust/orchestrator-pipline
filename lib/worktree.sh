# shellcheck shell=sh
# Git layout of a run (ADR-0010, ADR-0013). The project directory is the repo
# root; workspace mode adds the repos in orchestra.config.json. Every repo gets
# the same branches, checked out at the same relative path inside each
# worktree, so paths between repos keep working:
#   orchestra/run         integration branch, created from each repo's HEAD by
#                         `go`; root also carries the frozen design on top.
#                         Checked out in .worktrees/_run[/<path>]. The user's
#                         own branches are never touched.
#   orchestra/<task-id>   from the tip of orchestra/run, in
#                         .worktrees/<task-id>[/<path>], for root (it holds the
#                         others) and every repo in tasks[].repos; merged back
#                         --no-ff after ACCEPT. The task's other repos are
#                         detached checkouts of orchestra/run: readable, and
#                         any change there is found and discarded.
# The commit each checkout started from is recorded in .bus/tasks/<id>.json as
# `bases` (`base` is root's).

_WT_RUN=orchestra/run
_WT_NL='
'

_wt_dir() { printf '%s/.worktrees/%s\n' "$(project_root)" "$1"; }

# _wt_in <dir> <repo> — where a repo sits inside a worktree (or the project).
_wt_in() {
  _wip=$(repo_path "$2")
  if [ "$_wip" = . ]; then printf '%s\n' "$1"; else printf '%s/%s\n' "$1" "$_wip"; fi
}

# _wt_main <repo> — the repo's own checkout in the project directory.
_wt_main() { _wt_in "$(project_root)" "$1"; }

# _wt_branched <task-id|_run> — repos checked out on a branch: every repo for
# _run; root plus the task's repos for a task.
_wt_branched() {
  if [ "$1" = _run ]; then
    repo_names
  else
    { printf 'root\n'; task_repos "$1"; } | awk '!seen[$0]++'
  fi
}

# _wt_foreign_repos <task-id> — repos the task may not change (root included
# when it is not in tasks[].repos).
_wt_foreign_repos() {
  _wfr=$(task_repos "$1")
  repo_names | while IFS= read -r _r; do
    printf '%s\n' "$_wfr" | grep -qxF -- "$_r" || printf '%s\n' "$_r"
  done
}

# _wt_spec <repo> — pathspec for "everything in this checkout": root leaves
# out engine state. The other repos nested in root are gitignored by it
# (config_validate), so git skips them; naming them here would make `git add`
# fail on an ignored path.
_wt_spec() {
  printf '.\n'
  if [ "$1" = root ]; then
    printf '%s\n' ':(exclude).bus' ':(exclude).worktrees'
  fi
}

# _wt_git <git-args...> — git, with a fallback identity when none is set.
_wt_git() {
  if git config user.email >/dev/null 2>&1; then
    git "$@"
  else
    git -c user.name=orchestra -c user.email=orchestra@localhost "$@"
  fi
}

# _wt_add <task-id|_run> <repo> [detach] — check the repo out in the worktree:
# orchestra/run (from HEAD), orchestra/<task-id> (from orchestra/run), or a
# detached orchestra/run. Does nothing when the checkout exists.
_wt_add() {
  _wad=$(_wt_in "$(_wt_dir "$1")" "$2")
  [ ! -d "$_wad" ] || return 0
  _wam=$(_wt_main "$2")
  if [ "${3:-}" = detach ]; then
    git -C "$_wam" worktree add --detach "$_wad" "$_WT_RUN" >/dev/null 2>&1
    return
  fi
  if [ "$1" = _run ]; then _wab=$_WT_RUN; _was=HEAD; else _wab=orchestra/$1; _was=$_WT_RUN; fi
  if git -C "$_wam" show-ref --verify -q "refs/heads/$_wab"; then
    git -C "$_wam" worktree add "$_wad" "$_wab" >/dev/null 2>&1
  else
    git -C "$_wam" worktree add -b "$_wab" "$_wad" "$_was" >/dev/null 2>&1
  fi
}

# worktree_run_init — make sure orchestra/run exists in every repo and is
# checked out in .worktrees/_run, and that root's carries the frozen design as
# its latest commit.
worktree_run_init() {
  _root=$(project_root)
  git -C "$_root" rev-parse --verify -q HEAD >/dev/null 2>&1 \
    || die "orchestra go needs a git repository with at least one commit"
  _run=$(_wt_dir _run)
  for _r in $(repo_names); do
    _wt_add _run "$_r" \
      || die "could not create the $_WT_RUN worktree in $(_wt_in .worktrees/_run "$_r")"
  done
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

# worktree_base <task-id> [repo] — the commit the task's checkout of the repo
# (default root) started from.
worktree_base() {
  _wf=$(bus_dir)/tasks/$1.json
  [ -f "$_wf" ] || die "no task state for $1 (.bus/tasks/$1.json): base commit unknown"
  _wb=$(jq -r --arg r "${2:-root}" \
    '.bases[$r] // (if $r == "root" then .base else null end) // empty' "$_wf")
  [ -n "$_wb" ] || die "task $1 has no base commit for repo ${2:-root} in .bus/tasks/$1.json"
  printf '%s\n' "$_wb"
}

# worktree_create <task-id> — check out every repo for the task (see the top
# of this file) and record base/bases/branch/worktree. Checkouts that exist
# are kept, with their recorded base; the repos checked out on a branch now
# are printed, one per line.
worktree_create() {
  _wt=$(_wt_dir "$1")
  _foreign=$(_wt_foreign_repos "$1")
  _new='{}'
  bus_lock git
  for _r in $(repo_names); do
    _d=$(_wt_in "$_wt" "$_r")
    [ ! -d "$_d" ] || continue
    if [ "$_r" != root ] && printf '%s\n' "$_foreign" | grep -qxF -- "$_r"; then
      _wt_add "$1" "$_r" detach || { bus_unlock git; return 1; }
    else
      _wt_add "$1" "$_r" || { bus_unlock git; return 1; }
      printf '%s\n' "$_r"
    fi
    _new=$(printf '%s' "$_new" | jq -c --arg r "$_r" --arg b "$(git -C "$_d" rev-parse HEAD)" '.[$r] = $b')
  done
  bus_unlock git
  # shellcheck disable=SC2016 # jq variables
  task_update "$1" '.bases = ((.bases // {}) + $n) | .base = .bases.root | .branch = $br | .worktree = $w' \
    --argjson n "$_new" --arg br "orchestra/$1" --arg w "$_wt"
}

# Make untracked files visible to `git diff` without staging their content.
_wt_intent() {
  # shellcheck disable=SC2046 # one pathspec per line, no spaces
  git -C "$1" add -N -- $(_wt_spec "$2") >/dev/null 2>&1 || true
}

# _wt_changed <dir> <repo> <commit> — project-relative paths changed in the
# repo's checkout <dir> since <commit>: commits, edits and new files.
_wt_changed() {
  _wcp=$(repo_path "$2")
  _wt_intent "$1" "$2"
  # shellcheck disable=SC2046
  git -C "$1" diff --name-only "$3" -- $(_wt_spec "$2") | while IFS= read -r _f; do
    if [ "$_wcp" = . ]; then printf '%s\n' "$_f"; else printf '%s/%s\n' "$_wcp" "$_f"; fi
  done
}

# _wt_own <dir> — where the checkout's own work starts: its merge base with
# orchestra/run, so work merged in from orchestra/run does not count.
_wt_own() { git -C "$1" merge-base "$_WT_RUN" HEAD; }

# worktree_diff <task-id> <worktree> — everything the task changed since its
# bases, in every repo: commits, uncommitted edits and new files. Paths are
# project-relative (a/backend/src/x.ts).
worktree_diff() {
  for _r in $(repo_names); do
    _d=$(_wt_in "$2" "$_r")
    [ -d "$_d" ] || continue
    _p=$(repo_path "$_r")
    _b=$(worktree_base "$1" "$_r")
    _wt_intent "$_d" "$_r"
    if [ "$_p" = . ]; then
      # shellcheck disable=SC2046
      git -C "$_d" diff "$_b" -- $(_wt_spec "$_r")
    else
      git -C "$_d" diff --src-prefix="a/$_p/" --dst-prefix="b/$_p/" "$_b" -- .
    fi
  done
}

# worktree_changed_files <task-id> <worktree> — project-relative paths changed
# since the bases, in every repo.
worktree_changed_files() {
  for _r in $(repo_names); do
    _d=$(_wt_in "$2" "$_r")
    [ -d "$_d" ] || continue
    _wt_changed "$_d" "$_r" "$(worktree_base "$1" "$_r")"
  done
}

# worktree_foreign <task-id> — "<repo> <path>" for each change the task made
# in a repo it may not change (ADR-0013); empty when there are none.
worktree_foreign() {
  for _r in $(_wt_foreign_repos "$1"); do
    _d=$(_wt_in "$(_wt_dir "$1")" "$_r")
    [ -d "$_d" ] || continue
    _wt_changed "$_d" "$_r" "$(_wt_own "$_d")" | sed "s|^|$_r |"
  done
}

# worktree_foreign_discard <task-id> — undo the task's own changes in repos it
# may not change. Root keeps the other repos nested in it (gitignored).
worktree_foreign_discard() {
  for _r in $(_wt_foreign_repos "$1"); do
    _d=$(_wt_in "$(_wt_dir "$1")" "$_r")
    [ -d "$_d" ] || continue
    git -C "$_d" reset -q --hard "$(_wt_own "$_d")" || return 1
    # shellcheck disable=SC2046
    git -C "$_d" clean -fdq -- $(_wt_spec "$_r") >/dev/null 2>&1 || return 1
  done
}

# worktree_heads <task-id|_run> — "<repo> <commit>" for each branch checkout;
# compare two outputs to see whether anything moved.
worktree_heads() {
  for _r in $(_wt_branched "$1"); do
    printf '%s %s\n' "$_r" "$(git -C "$(_wt_in "$(_wt_dir "$1")" "$_r")" rev-parse HEAD)"
  done
}

# worktree_commit <task-id> <message> — commit whatever the agent left
# uncommitted, in each of the task's branch checkouts.
worktree_commit() {
  for _r in $(_wt_branched "$1"); do
    _d=$(_wt_in "$(_wt_dir "$1")" "$_r")
    _wt_git -C "$_d" add -A >/dev/null 2>&1 || return 1
    if ! git -C "$_d" diff --cached --quiet; then
      _wt_git -C "$_d" commit -q -m "$2" || return 1
    fi
  done
}

# _wt_rollback <lines> — "git reset --hard" each "<commit> <dir>" line.
_wt_rollback() {
  printf '%s' "$1" | while read -r _c _d; do
    [ -n "$_c" ] && git -C "$_d" reset -q --hard "$_c"
  done
}

# worktree_update <task-id> — merge what reached orchestra/run since the task
# branched into the task branch, in every repo of the task. On a conflict in
# any repo all of them are put back and 1 is returned. Caller holds the git
# lock.
worktree_update() {
  _wu_done=""
  for _r in $(_wt_branched "$1"); do
    _d=$(_wt_in "$(_wt_dir "$1")" "$_r")
    _h=$(git -C "$_d" rev-parse HEAD)
    if ! _wt_git -C "$_d" merge -q --no-edit "$_WT_RUN" >/dev/null 2>&1; then
      git -C "$_d" merge --abort >/dev/null 2>&1 || true
      _wt_rollback "$_wu_done"
      return 1
    fi
    _wu_done="$_wu_done$_h $_d$_WT_NL"
  done
}

# worktree_merge <task-id> — merge orchestra/<task-id> into orchestra/run in
# every repo of the task. If any merge fails, the run tips merged so far are
# restored, so orchestra/run never holds part of a task, and 1 is returned.
# Caller holds the git lock (or no run is active).
worktree_merge() {
  _wm_done=""
  _wm_msg="orchestra: merge $1 — $(plan_task "$1" '.desc')"
  for _r in $(_wt_branched "$1"); do
    _d=$(_wt_in "$(_wt_dir _run)" "$_r")
    _h=$(git -C "$_d" rev-parse HEAD)
    if ! _wt_git -C "$_d" merge -q --no-ff -m "$_wm_msg" "orchestra/$1" >/dev/null 2>&1; then
      git -C "$_d" merge --abort >/dev/null 2>&1 || true
      _wt_rollback "$_wm_done"
      return 1
    fi
    _wm_done="$_wm_done$_h $_d$_WT_NL"
  done
}

# worktree_remove <task-id> — drop the task's checkouts, nested repos first;
# the branches are kept.
worktree_remove() {
  _wt=$(_wt_dir "$1")
  bus_lock git
  for _r in $(repo_names | awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }'); do
    git -C "$(_wt_main "$_r")" worktree remove --force "$(_wt_in "$_wt" "$_r")" >/dev/null 2>&1 || true
  done
  bus_unlock git
}

# worktree_drop_branches <task-id> — delete orchestra/<task-id> in every repo.
worktree_drop_branches() {
  for _r in $(repo_names); do
    git -C "$(_wt_main "$_r")" branch -D "orchestra/$1" >/dev/null 2>&1 || true
  done
}
