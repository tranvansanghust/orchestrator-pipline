# ADR-0010: Phase-2 daemon — branches, resume, retries

- Status: accepted
- Date: 2026-11-25

## Context

Roadmap step 4 runs the approved plan end to end with one agent at a time.
It must never damage the user's work, survive being stopped, and keep a human
out of the loop until the human is actually needed.

## Decision

1. **Branches.** `orchestra go` creates `orchestra/run` from HEAD, checked out
   in `.worktrees/_run`, and commits the frozen design (docs, plan, traceability,
   config) on it, so uncommitted phase-1 edits still reach the agents. Each task
   gets `orchestra/<id>` + `.worktrees/<id>` from the tip of `orchestra/run`
   and is merged back `--no-ff` after ACCEPT. The user's branch and working
   tree are never touched; nothing is pushed.

2. **One task at a time, in plan order**, driven by the state machine in
   `.bus/tasks/<id>.json`. Every transition is guarded and logged.

3. **Resume.** All state lives in `.bus/`. `orchestra go` on a frozen design
   whose hashes still match resumes from each task's current state (an agent
   run interrupted mid-flight is started again). If the design changed, `go`
   lists the changed/deleted/new files and refuses unless `--refreeze`, which
   re-runs the readiness check. `orchestra stop` leaves a flag; the run stops
   after its current step. `--no-run` only approves and freezes.

4. **Agents write code and tests.** Phase 1 produces a test plan, not test
   code. The agent writes the done_when test files from the plan; the
   reviewer rubric rejects tests that check nothing.

5. **Retries.** VERIFY failure → the failing checks' output (last 60 lines
   each) goes back to the agent, up to `max_verify_rounds`, then BLOCKED.
   REJECT → back to the agent with `fixes_requested` in the same worktree, up
   to `max_reject_rounds`, then ESCALATED. A timed-out agent
   (`execution.agent_timeout_s`) is killed and the attempt goes through VERIFY
   with a note that it timed out.

6. **Worktree setup.** `stack.setup` (e.g. `npm ci`) runs once per new task
   worktree; `init` pre-fills it from the detected stack.

7. **FR status** (`planned → implemented → accepted`) is computed from task
   states into `.bus/traceability.status.json`; the frozen `traceability.json`
   is never modified.

8. **Exit codes.** `go` exits 0 when every task is DONE or the run was
   stopped, 4 when tasks are BLOCKED, ESCALATED or waiting on them.

## Consequences

- A failed run costs nothing to inspect: worktrees, prompts, verify logs and
  review rounds are all on disk.
- Merge conflicts cannot happen while tasks run sequentially (each branches
  from the latest `orchestra/run`); they become possible with the pool.
- Escalated tasks wait for `orchestra resolve` (roadmap step 6).
