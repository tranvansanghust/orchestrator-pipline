# ADR-0006: Adapter execution model and agent selection

- Status: accepted
- Date: 2026-11-25

## Context

Phase 2 drives several agent CLIs. tmux is not installed yet, and the first
CLIs (opencode, claude) are headless one-shot processes, not TUIs. We also need
to settle how a project picks which agents run.

## Decision

1. **Agent selection is static (option a).** Agents are declared in
   `orchestra.config.json`; the scheduler matches them to tasks by skill. No
   per-task agent field and no interactive picker.

2. **Two execution models.**
   - *run-to-exit* (default): the CLI runs once and exits; "done" = process
     exit. No tmux. Shared helpers `run_to_exit_dispatch` / `run_to_exit_wait`
     in `lib/adapter.sh` run the CLI in the background in the task worktree and
     record `.bus/agents/<task>.{log,pid,exit}`.
   - *pane-parse*: a TUI-only CLI driven through a tmux pane, parsed for
     completion. Deferred to roadmap step 5; its mess stays in its own adapter.

3. **Four-function interface, agent name first.** `adapter_<fn> <agent> ...`.
   `adapter_spawn` verifies the CLI **and its mode** (the ZCode lesson: a CLI
   may default to a mode that never signals completion). `adapter_wait` returns
   0 / 1 / 124 (done / failed / timeout).

4. **Adapters read config only via `agent_field`**, never by parsing JSON, so
   config shape lives in one place.

5. **`mock` is the reference adapter** and the offline test fixture; it makes
   no network calls. Real adapters (opencode, claude) have online smoke tests
   gated behind `ORCHESTRA_ONLINE=1` so CI stays free and deterministic.

6. **Unattended auto-approve is acceptable** (`opencode --auto`,
   `claude --dangerously-skip-permissions`) because each task runs in its own
   git worktree and orchestra gates destructive actions itself at MERGE.

## Consequences

- Step 3 works and is testable with no tmux and no API spend (via `mock`).
- The scheduler/pool only ever see the four functions and skills, so swapping
  or adding an agent is one file plus a config entry.
- The agent's own output is not interpreted as truth; VERIFY decides done.
