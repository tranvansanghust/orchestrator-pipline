# ADR-0012: Parallel pool and integration build

- Status: accepted
- Date: 2026-11-25

## Context

ADR-0010 ran one task at a time. With several agents configured, independent
tasks should run together; that brings two new failure modes the sequential
daemon could not have: two tasks racing for one agent or one git operation,
and a task that passed VERIFY alone but breaks next to work merged meanwhile.

## Decision

1. **Workers.** The daemon runs up to `execution.max_parallel` tasks at once
   (default: the number of agents), each in a background worker that drives
   the task's state machine. An agent works on one task at a time; the parent
   assigns the agent before starting the worker, so two workers never share
   one. Workers signal completion with a marker file (a finished background
   process is a zombie until reaped, so `kill -0` cannot tell).

2. **Serialized git.** Worktree creation and removal, and the whole
   integrate step, hold a `.bus/locks/git` mutex (`mkdir` lock, recording the
   holder's pid; a lock whose holder died is taken over).

3. **Integrate, don't merge blind.** After ACCEPT the task's work is
   committed, then `orchestra/run` is merged into the task branch. If that
   brought anything in, VERIFY runs again on the combined code. Conflict or a
   failing re-VERIFY → ESCALATED (`merge` / `integration`); only a clean,
   green branch is merged into `orchestra/run`. `orchestra resolve accept`
   uses the same step.

4. **Integration build** (`execution.integration`): `stack.integration` runs
   on `orchestra/run` after `stack.setup`, once at the end of a run that
   merged something (`end`, default), after every merge (`merge`), or never
   (`off`). The result is `.bus/integration.json`; a failure is an inbox entry
   (`integration.md`) and makes `go` exit 4.

5. A worker that leaves its task where it found it (an engine bug) is not
   relaunched in the same run; the daemon warns instead of looping.

## Consequences

- `max_parallel: 1` reproduces the sequential daemon exactly.
- Tasks with overlapping `scope` will conflict more often in parallel; the
  breakdown should keep parallel tasks apart, and the conflict escalates
  rather than corrupting `orchestra/run`.
