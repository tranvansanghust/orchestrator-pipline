---
description: Crystallise the breakdown into plan.json and traceability.json
---

You are producing the two machine-read handoff files from the phase-1 docs.
Do not invent anything: every value comes from a document. If a document is
missing information, stop and say which.

1. Read `docs/01-SRS.md`, `docs/06-test-plan.md`, `docs/08-task-breakdown.md`,
   every `docs/specs/T<n>.md` and `orchestra.config.json`.
2. Write `plan.json` (schema: `schemas/plan.schema.json` in the orchestra
   install; `orchestra --help` locates the engine):
   - `orchestra_version`: from orchestra.config.json;
   - `goal`: one line from the PRD;
   - `approved`: `false` (only `orchestra go` sets it to true);
   - one task per `### T<n>` heading, in dependency order: `id`, `desc`,
     `deps`, `skill`, `spec_file` (`docs/specs/T<n>.md`), `areas`, `scope`
     (globs of the files the task should change, from its spec), and
     `done_when`: `tests_pass` (the task's test files from the test plan),
     `typecheck: true` when the stack has a typecheck command, `build: true`
     on the last task of a milestone.
   - No `build`/`test` commands here: they live in orchestra.config.json.
3. Write `traceability.json`: one key per FR, `{desc, tasks, tests,
   acceptance, status: "planned"}`, where `tasks` are the tasks whose
   Requirements line names the FR and `tests` the FR's files in the test plan.
4. Validate both if `check-jsonschema` is available, then run
   `orchestra go --no-run --profile <profile>` only if the user asks; otherwise
   suggest `/handoff` next and then `/go`.

Report the task count, the FR → task map, and anything inconsistent.
