# ADR-0009: Hard escalation rules guard ACCEPT only

- Status: accepted (supersedes ADR-0008 §5)
- Date: 2026-11-25

## Context

ADR-0008 applied the confidence, severity and scope rules to every
non-ESCALATE verdict. The first real review showed the cost: a clear,
agent-fixable pagination bug came back as REJECT with two high concerns and
was escalated to a human anyway.

## Decision

The risk rules exist to stop a wrong change from being merged, and only an
ACCEPT is merged. So:

- **ACCEPT only**: confidence below `escalation.confidence_threshold`, any
  high/critical concern, a changed file outside `scope`, a task area in
  `escalation.always_human` → ESCALATE.
- **Any verdict**: `needs_human: true` → ESCALATE. The reviewer is asking a
  question the coding agent cannot answer, so sending the task back to the
  agent would not help.
- A REJECT otherwise goes back to the agent with `fixes_requested`; repeated
  rejection is caught by the `max_reject_rounds` rule (with the daemon).

## Consequences

- Fewer human interruptions for bugs the agent can fix.
- A REJECT with a critical security concern still returns to the agent first;
  if the agent cannot fix it within `max_reject_rounds`, the task escalates.
