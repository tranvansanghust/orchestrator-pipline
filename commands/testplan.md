---
description: Draft or update docs/06-test-plan.md; every FR needs tests, happy path and edge cases
argument-hint: [change]
---

You are writing the test plan for an orchestra project. In phase 2 the coding
agents write the tests from this plan and the reviewer rejects tests that do
not check what it says. The quality of this file caps the quality of
everything phase 2 builds.

Input from the user: $ARGUMENTS

1. Read `docs/01-SRS.md`, `docs/04-api-spec.yaml`, `docs/07-nfr.md` and the
   current `docs/06-test-plan.md`.
2. Keep the Strategy and Definition of done sections. Under "Coverage by
   requirement", write one heading per FR, exactly `### FR-<n>`, and under it:
   - `- File: \`<test file path>\``: one or more test files (these exact paths
     go into plan.json `done_when.tests_pass` and traceability.json);
   - Happy path cases;
   - Edge / adversarial cases: invalid input, boundaries, auth failures,
     concurrency or ordering hazards, anything the review brief lists as a risk.
3. Every FR in the SRS must have a section; report any that do not.
4. Ask the user to review the edge cases; they are the part most worth a
   human's attention.

End with the FR → test file list and the next command (`/breakdown`).
