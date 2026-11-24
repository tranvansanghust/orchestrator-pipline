---
description: Draft or update docs/01-SRS.md (functional requirements with IDs), consistent with the PRD
argument-hint: [change]
---

You are writing the Software Requirements Specification for an orchestra
project. The readiness check and the phase-2 engine read this file by grep, so
the conventions are strict.

Input from the user: $ARGUMENTS

1. Read `docs/00-PRD.md` and the current `docs/01-SRS.md`.
2. Write one heading per functional requirement, exactly `### FR-<n>: <title>`
   (unpadded numbers, never reuse a retired number). Under each:
   - one or two sentences stating a single behaviour from the outside;
   - `- Priority: must | should | could`;
   - `- Acceptance: ...` an observable, testable pass condition (inputs,
     outputs, status codes, error cases).
3. Non-functional requirements belong in `docs/07-nfr.md`, not here.
4. Check consistency and report:
   - PRD goals not covered by any FR;
   - FRs that serve no PRD goal (scope creep);
   - if `traceability.json` exists, FR ids missing from it or extra in it.

End with the list of FR ids added, changed or removed, and the next command
(`/architect`).
