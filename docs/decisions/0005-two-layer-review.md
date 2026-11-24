# ADR-0005: Two-layer review, source-tagged evidence, per-role models

- Status: accepted
- Date: 2026-11-25

## Context

Studying `zcode-pentest-workflows` (LazyArtex orchestration) surfaced three
patterns that strengthen phase 2 against its biggest risk — a confident but
wrong reviewer (risk #3). Folding them in now, while the schemas are young, is
cheaper than later.

## Decision

1. **Two-layer review.** The reviewer emits a `verdict.json`. A second role, the
   confirmer, reads the verdict against the evidence bars (not re-running the
   work) and emits `confirmation.json` with `upheld`, the `supported` verdict,
   and a reason. The engine's effective verdict is the reviewer's when
   `upheld`, otherwise the `supported` one. **A downgrade never raises trust**:
   an ACCEPT may fall to REJECT or ESCALATE, never the reverse. This is the
   "not sure → STOP" rule made mechanical.

2. **Source-tagged evidence.** Every item in `verdict.evidence` carries a
   `source`: `verify_report` (trusted machine output), `diff` / `contract` /
   `spec` / `review_brief` (phase-1 or code artifacts), `agent_claim` (the
   agent's own narrative — untrusted, weakest) or `reviewer_inference`. The
   agent's output is data, not truth; an ACCEPT resting only on `agent_claim`
   or `reviewer_inference` is exactly what the confirmer drops to ESCALATE.

3. **Per-role models.** Each `brain` role (`planner`, `reviewer`, optional
   `confirmer`) is a command string or `{cmd, model}`. This allows a strong
   model for the review and a cheaper one for the confirmer's check, the way
   the reference workflow pins a strong worker and a cheap verdict reviewer.

## Consequences

- New schema `confirmation.schema.json`; `verdict.schema.json` now requires
  non-empty, source-tagged evidence and `fixes_requested` on REJECT.
- `lib/review.sh` gains a confirm step after the reviewer (roadmap step 3);
  `brain.confirmer` defaults to `brain.reviewer` when omitted.
- The downgrade rule (ACCEPT → ESCALATE, never upward) is engine logic, not
  expressible across the two files in JSON Schema; it is covered by engine
  tests when `lib/review.sh` lands.
