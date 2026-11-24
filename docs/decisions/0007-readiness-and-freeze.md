# ADR-0007: Readiness check, freeze and runner VERIFY

- Status: accepted
- Date: 2026-11-25

## Context

`orchestra go` is the boundary between phase 1 (humans + Claude TUI) and
phase 2 (automation). It must refuse an incomplete design, and once it accepts
one, phase 2 must be able to tell if the design changed afterwards. Separately,
the runner is the only judge of "done".

## Decision

1. **Freeze = approval flag + hash manifest, no auto-commit.** When the
   readiness check passes, `go` sets `approved: true` in `plan.json` and writes
   `.bus/frozen.json` with the SHA-256 of every file under `docs/` plus
   `plan.json` and `traceability.json`. It prints a reminder to commit; it does
   not commit on the user's behalf.

2. **OpenAPI validation degrades gracefully.** `api_spec` uses `redocly lint`
   or `swagger-cli validate` when either is on PATH. Otherwise it runs a light
   structural check (`openapi: 3.x` and a top-level `paths:`) and prints a NOTE
   saying full validation was skipped. No YAML parser is required, which
   avoids depending on the local Python (3.7 on the reference machine broke
   the Python OpenAPI validator).

3. **`data_model` is a light cross-reference** (strict profile only): every
   `components.schemas` entry must be mentioned in `05-data-model.md`. Field-by-
   field comparison is out of scope; it would be brittle.

4. **Cross-checks belong to the readiness check, not the schemas**: FR sets
   agree across SRS / traceability / test plan, every task serves an FR,
   done_when tests equal traceability tests, deps are known and acyclic,
   `spec_file` is `docs/specs/<id>.md` and exists, referenced ADRs exist, every
   NFR has a measurable target.

5. **Runner VERIFY** runs `done_when` in the task worktree: `tests_pass` via
   `stack.test_one` (with `{files}` replaced by the space-separated list),
   `typecheck`, `build`, and each `commands[]` entry. It writes
   `.bus/verify/<task>.json` (`schemas/verify.schema.json`); the task passes
   only if every check exited 0.

## Consequences

- `go` is idempotent: re-running it on a ready plan refreshes the manifest.
- Phase 2 can compare the live files against `.bus/frozen.json` to detect
  design drift (used when the daemon lands).
- File paths with spaces are not supported in test lists or task ids.
