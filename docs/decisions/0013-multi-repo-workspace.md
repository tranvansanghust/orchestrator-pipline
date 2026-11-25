# ADR-0013: Multi-repo workspace

- Status: accepted
- Date: 2026-11-25

## Context

Phase 2 leans on git for everything that keeps it safe: a worktree per task,
the diff the reviewer reads, integrate-then-merge, the frozen design commit
and cheap rollback (ADR-0010, ADR-0012). All of it runs against one repo,
the one `project_root` resolves to. Many real projects are a plain directory
holding several repos side by side (backend, frontend, shared lib), and the
interesting tasks change more than one of them at once.

## Decision

1. **The workspace is a meta-repo.** The project directory is a git repo of
   its own, named `root`: it holds `docs/`, `plan.json`, the config and any
   workspace-level files (`docker-compose.yml`, e2e). The other repos live
   in subdirectories that root gitignores. A single-repo project is the
   special case with only `root`; nothing changes for it.

2. **Config.** `repos: { "<name>": { "path": "<dir>", "stack": {...} } }`.
   Each repo has its own full `stack`; there is no inheritance. The top-level
   `stack` belongs to `root`, and `stack.integration` builds the whole
   workspace. `root` is reserved. Paths are relative, have no dot segments,
   must not nest, and each must be the top of a git repo with a commit that
   root ignores (`config_validate`).

3. **Plan.** `tasks[].repos` lists the repos a task may change (default
   `["root"]`). `scope` globs and `done_when.tests_pass` paths are relative to
   the project directory; the owning repo of a path is the configured repo
   whose path prefixes it, otherwise `root`. The readiness check
   (`plan_schema`) fails a task whose repos are unknown or whose scope or
   tests fall outside them.

4. **Worktrees** mirror the workspace, so relative paths between repos keep
   working:

   ```
   .worktrees/_run/            orchestra/run of root
   .worktrees/_run/<path>/     orchestra/run of each repo
   .worktrees/<task>/          orchestra/<task> of root
   .worktrees/<task>/<path>/   orchestra/<task> of each repo in tasks[].repos
   .worktrees/<task>/<path>    symlink to _run/<path> for every other repo
   ```

   Each repo gets the same branch names; a task's `base` is recorded per repo.
   Untouched repos are visible read-only by convention. A symlink cannot
   enforce that, so after each agent turn the `_run` checkouts it could
   reach are checked; any change is discarded and the attempt fails VERIFY
   with feedback naming the repo.

5. **VERIFY** groups `tests_pass` by owning repo and runs each repo's
   `test_one` in that repo's worktree with repo-relative paths; `typecheck`
   and `build` run for every repo of the task that defines them; `commands`
   run in the task's root worktree. `stack.setup` runs per repo when its
   worktree is created.

6. **Review** gets one diff: every repo's diff with paths prefixed by the
   repo path, so scope checks and the reviewer see project-relative paths.

7. **Integrate as one unit.** Under the git lock: merge `orchestra/run` into
   the task branch in every repo of the task; any conflict aborts all of them
   and escalates. Re-VERIFY if anything came in. Then merge each task branch
   into its `orchestra/run`; these cannot conflict, since each task branch
   already contains its run tip. The run tips are recorded first and restored
   if a merge still fails, so `orchestra/run` never holds half a task.
   Integration runs `stack.integration` in `.worktrees/_run`.

8. **Versioning.** Both fields are optional and old configs and plans stay
   valid, so this ships as a minor version (0.3.0). Bumping the major on any
   schema change (ADR-0002, CHANGELOG) is meant for breaking changes.

## Consequences

- Built in four steps: schema and readiness (this ADR), worktrees, daemon /
  runner / review, then `init` (detects child repos and gitignores them),
  `doctor`, `status`, `resolve`, an example and docs.
- `project_root` resolves to the enclosing git repo; run from inside a child
  repo it finds the child. Step 4 makes it look for the nearest directory
  with `orchestra.config.json` first.
- Merging across repos is not atomic at the git level; the recorded run tips
  are the rollback, and the git lock keeps other workers out meanwhile.
