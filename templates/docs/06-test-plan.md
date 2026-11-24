# Test Plan

<!--
Conventions (read by the readiness check):
- One `### FR-<n>` heading per requirement in 01-SRS.md.
- Under it, list test files and cases. Cover the happy path AND edge /
  adversarial cases — weak tests cap the quality of everything phase 2 does.
- Test files listed here must match traceability.json and plan.json done_when.
-->

## Strategy

<!-- Levels (unit / integration / e2e), tooling, test data, environments. -->

## Definition of done

A task is done when every file in its `done_when.tests_pass` passes, plus
typecheck/build when its `done_when` asks for them — run by the engine, not
claimed by the agent.

## Coverage by requirement

### FR-1

- File: `test/<name>.test.ts`
- Happy path:
- Edge / adversarial:
