# Review rubric

> Default rubric, appended to the reviewer's instructions. A project replaces
> it with its own `docs/rubric.md`.

Check, in this order:

1. **Spec**: does the diff do what the task spec and its acceptance criteria say, no more and no less?
2. **Contract**: do routes, functions and types match `04-api-spec.yaml` (paths, status codes, field names and types)?
3. **Tests**: do the tests in `done_when` actually assert the acceptance criteria, including the edge and adversarial cases from the test plan? Tests that pass trivially (no assertions, the subject mocked out) are a REJECT.
4. **Review brief**: the invariants in `09-review-brief.md` hold. Touching a red line is an ESCALATE.
5. **Security**: input validation, authentication and authorisation, secrets, injection, data exposure.
6. **Scope**: changes unrelated to the task are scope creep; REJECT and list them.
7. **Architecture**: the boundaries and layering in `02-architecture.md` are respected.
8. **Quality**: readability, explicit error handling, no dead code, the project conventions.

Concern severity:

| Severity | Meaning |
|---|---|
| critical | security hole or data loss |
| high | wrong behaviour on a main path |
| medium | wrong edge case, weak test |
| low | style, minor issue |
| info | observation, no action needed |
