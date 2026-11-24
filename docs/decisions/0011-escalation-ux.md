# ADR-0011: Escalation UX — inbox, handoff, resolve, cockpit, gates

- Status: accepted
- Date: 2026-11-25

## Context

The daemon (ADR-0010) parks tasks as BLOCKED or ESCALATED with an inbox file.
A human now needs a fast path from "something stopped" to "decided", and the
design's gates (`vcs.gate`) need to mean something in a pipeline that never
pushes or deploys.

## Decision

1. **`orchestra resolve <task> <action>`** for BLOCKED or ESCALATED tasks:
   - `accept` (ESCALATED only, VERIFY must have passed): commit and merge the
     change as it is → DONE;
   - `reject "<msg>"`: back to the agent with the message;
   - `retry ["<msg>"]`: back to the agent after an outside problem was fixed;
   - `amend-spec "<msg>"`: the design was wrong and has been edited; requires
     a detected design change, re-runs the readiness check, re-freezes,
     commits the new design on `orchestra/run`, and restarts the task from
     scratch (worktree, branch, verify report and review rounds set aside).
   `reject`, `retry` and `amend-spec` reset the retry budgets: a human looked.
   The inbox entry moves to `.bus/escalations/resolved/`.

2. **Run lock.** `orchestra go` writes `.bus/run.pid`. `accept` and
   `amend-spec` refuse while a run is active (both touch `orchestra/run`);
   `reject` and `retry` only flip state, so a running daemon picks the task up.

3. **TUI handoff.** `orchestra resolve <task>` with no action opens the
   planner (`brain.planner`, normally `claude`) with the `/resolve` procedure
   and the inbox entry as its first prompt — in a new window of the cockpit
   tmux session when one runs, otherwise in the current terminal.

4. **Cockpit.** `orchestra design` opens tmux session `orchestra-<project>`:
   Claude on the left, `orchestra status --watch` on the right. Without tmux
   (or with `ORCHESTRA_NO_TMUX=1`) it opens Claude in place. Escalations post
   a tmux message to the cockpit when it runs.

5. **Gates.** The engine never pushes, deploys or deletes remote state. The
   gate entries that are also task areas, `migration` and `delete`, escalate
   an ACCEPT like `always_human` does; `vcs.gate` defaults to all four, so a
   migration task always reaches a human unless the project removes it.

## Consequences

- The common resolutions are one command; the uncommon ones get Claude with
  the full context, not a blank session.
- Merges stay single-writer even with a human acting during a run.
