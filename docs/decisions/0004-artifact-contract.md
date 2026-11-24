# ADR-0004: Phase-1 artifact contract

- Status: accepted
- Date: 2026-11-25

## Context

`ORCHESTRA-context.md` sketches `plan.json`, the config and traceability, but
leaves overlaps (the same fact in two files) and places the readiness check
cannot read reliably from POSIX sh.

## Decision

1. **Specs are committed**: `spec_file` is `docs/specs/T<n>.md`. `.bus/` holds
   only runtime state.
2. **Build/test commands live only in the config** (`stack`). `plan.json` has
   no `build` block.
3. **Running single test files** goes through `stack.test_one`, a command
   containing `{files}`. `done_when` keys: `tests_pass[]` (required, ≥1),
   `typecheck`, `build`, `commands[]`.
4. **`traceability.json` is the only FR → task → test mapping.** `plan.json`
   carries execution data only (deps, skill, spec, done_when, areas, scope);
   the per-task `tests` field from the sketch is dropped in favour of
   `done_when.tests_pass`. The readiness check cross-checks both files.
5. **Tasks declare `areas`** (matched against `escalation.always_human`) and an
   optional `scope` (globs; a diff outside them escalates).
6. **`approved`** is written `false` by `/plan`; only `orchestra go` sets it
   `true`.
7. **Markdown docs follow grep-able conventions**, documented in each
   template: `### FR-1: …` in the SRS, `### NFR-1: …` followed by a
   `| Metric | Target | How measured |` table in the NFR doc, `### T1: …` in the
   task breakdown (ids are unpadded: `FR-1`, `T1`), ADR files named
   `NNNN-slug.md` and referenced as `ADR-NNNN`. Anything that needs precision is read from JSON.
8. **Blank templates and the worked example are separate**:
   `templates/docs/` is copied by `init`; `examples/blog-api/` is a complete
   set used as reference and as the readiness-check test fixture.
9. **Template headings and guidance are English**; project content may use
   any language. Diagrams use Mermaid.
10. **Traceability status**: `planned → implemented` (tests green)
    `→ accepted` (merged).

## Consequences

- Every fact has one home; the readiness check verifies the joins
  (plan ↔ traceability ↔ SRS ↔ test plan) instead of trusting duplicates.
- Schema validation alone cannot catch unknown deps, cycles or
  `spec_file` ≠ `id`; those belong to the readiness check (roadmap step 1).
