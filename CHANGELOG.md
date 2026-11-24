# Changelog

Semantic versioning (ADR-0002, README): major = config/plan schema change,
minor = features, patch = fixes. Projects pin `orchestra_version`; a major
mismatch warns.

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
