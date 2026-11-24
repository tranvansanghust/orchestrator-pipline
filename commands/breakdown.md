---
description: Draft or update docs/08-task-breakdown.md; tasks must cover every FR
argument-hint: [change]
---

You are breaking the design into tasks that coding agents will each implement
alone, in their own git worktree, followed by one review.

Input from the user: $ARGUMENTS

1. Read `docs/01-SRS.md`, `docs/02-architecture.md`, `docs/04-api-spec.yaml`,
   `docs/05-data-model.md`, `docs/06-test-plan.md` and the current
   `docs/08-task-breakdown.md`.
2. Size each task for one agent and one reviewable diff: one concern, its own
   tests, a few hundred lines at most. Prefer more, smaller tasks.
3. Write a Mermaid dependency graph, then one heading per task, exactly
   `### T<n>: <title>`, with:
   - `- Requirements: FR-<n>, ...` (every task serves at least one FR);
   - `- Depends on: T<m>, ... | none` (no cycles);
   - `- Skill: <skill>` (must match an agent's skills in orchestra.config.json);
   - `- Areas: auth | payment | migration | ... | none` (sensitive areas
     always go to a human before merge);
   - `- Spec: docs/specs/T<n>.md`.
4. Write each `docs/specs/T<n>.md` from `docs/specs/T0-template.md`: Goal,
   Contract (operationIds, functions, types it implements or relies on),
   Acceptance tests (the test files from the test plan), Out of scope, Notes.
   Write it so a capable engineer with no other context could finish the task.
5. Report FRs not covered by any task and skills no configured agent has.

End with the task list and the next command (`/plan`).
