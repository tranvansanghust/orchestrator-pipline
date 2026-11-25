# Changelog

Semantic versioning (ADR-0002, README): major = config/plan schema change,
minor = features, patch = fixes. Projects pin `orchestra_version`; a major
mismatch warns.

## 0.3.0 — 2026-11-25

Multi-repo workspaces (ADR-0013). Additive: 0.2 configs and plans are
unchanged and still valid.

- Config `repos`: further git repos inside the project directory, each with
  its own `stack`; the project directory is the repo `root`. Plan
  `tasks[].repos` names the repos a task may change.
- Every repo gets `orchestra/run` and `orchestra/<task>`, nested in the
  worktrees as in the workspace. Repos a task may not change are read-only
  detached checkouts; changes there are discarded and fail VERIFY (`scope`).
- VERIFY, `stack.setup` and the integration build run per repo; review gets
  one diff with project-relative paths; integrate and merge are all or
  nothing across repos.
- `orchestra init` detects child repos, git-initialises the workspace and
  gitignores them; `orchestra` finds the project from any subdirectory;
  `doctor`, `status` and the inbox show repos; `/breakdown` and `/plan` write
  `repos`. Example: `examples/workspace/make-demo.sh`.

## 0.2.0 — 2026-11-25

First version that runs end to end.

- Phase 1: `orchestra init` (stack detection, scaffolding), slash commands
  `/prd` … `/handoff`, `/go`, `/status`, `/resolve`; artifact contract with
  JSON Schemas and grep-able Markdown conventions; `examples/blog-api`.
- `orchestra go`: design readiness check (lite / standard / strict), freeze
  with drift detection and `--refreeze`, resumable phase-2 run.
- Phase 2: worktree per task on an `orchestra/run` integration branch, runner
  VERIFY with failure feedback, two-layer review (no-tool reviewer with
  source-tagged evidence + confirmer that never raises trust), hard
  escalation rules guarding ACCEPT, gates, parallel workers (one task per
  agent), integrate-then-merge with re-VERIFY, integration build.
- Humans: inbox in `.bus/escalations/`, `orchestra resolve` (accept / reject /
  retry / amend-spec / Claude handoff), `orchestra design` tmux cockpit,
  `orchestra status --watch`, `orchestra stop`, `orchestra doctor`.
- Adapters: `claude`, `opencode`, `zcode` (headless), `mock`.

## 0.1.0 — 2026-11-24

Skeleton.
