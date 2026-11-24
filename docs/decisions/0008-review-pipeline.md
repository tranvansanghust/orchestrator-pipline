# ADR-0008: Review pipeline — context pack, structured verdicts, hard rules

- Status: accepted
- Date: 2026-11-25

## Context

ADR-0005 defined the two-layer review and source-tagged evidence. This ADR
fixes how a review round actually runs on the `claude` CLI, verified against
the real CLI (structured output lands in `.structured_output` of the
`--output-format json` envelope).

## Decision

1. **No-tool reviewer.** Reviewer and confirmer run `claude -p` with
   `--tools ""`, `--system-prompt` (engine instructions + rubric) and the
   context pack on stdin. The reviewer judges only the pack; agent-written
   content cannot make it run anything. Agentic review (file access) is
   deferred to complex tasks later.

2. **Structured output, validated twice.** The call passes
   `--json-schema` (our schema minus `$schema`/`$id`/`allOf`), then the engine
   validates the result against the full schema and checks `task`. Invalid
   output is retried once with the error appended; invalid again becomes a
   synthetic ESCALATE. A broken reviewer never yields ACCEPT.

3. **Context pack from artifacts.** Never dropped: task + spec, verify report,
   diff since the recorded base commit, the done_when test files, the previous
   round's verdict. Optional, dropped in this order to fit
   `review.max_pack_bytes`: conventions, contracts, architecture, brief. If the
   pack still does not fit, the task escalates without calling the reviewer.
   Agent-written content is wrapped in `<untrusted-data id="<nonce>">` with a
   random per-round id, so a fake closing tag inside the diff cannot end the
   block.

4. **Confirmer only on ACCEPT.** An ESCALATE is already a stop; a wrong REJECT
   costs one agent round and is bounded by `max_reject_rounds`.

5. *(Superseded by ADR-0009.)* **Hard rules on the post-confirm verdict**, each forcing ESCALATE:
   confidence below `escalation.confidence_threshold`; any high/critical
   concern; `needs_human`; a changed file outside `scope` (done_when test files
   are always in scope); and, for ACCEPT only, a task area in
   `escalation.always_human`. Rules needing history (reject rounds ≥ K) come
   with the daemon.

6. **Per-call spend cap** `review.max_budget_usd` (default 1) passed as
   `--max-budget-usd`; each round records `cost_usd` in `decision.json`.

7. **Every round is kept** in `.bus/review/<task>/round-<n>/` (pack, raw
   output, verdict, confirmation, decision) so round n+1 can see round n.

## Consequences

- Offline tests use `test/fixtures/fake-claude`; one online test
  (`ORCHESTRA_ONLINE=1`) exercises the real CLI. First real run: a buggy
  pagination change got REJECT with two high concerns, escalated by the
  severity rule, cost $0.14.
- §5 is superseded by ADR-0009: the risk rules now guard ACCEPT only.
