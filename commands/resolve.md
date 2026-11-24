---
description: Resolve a blocked or escalated phase-2 task with the user
argument-hint: <task> [accept | reject "<msg>" | retry ["<msg>"] | amend-spec "<msg>"]
---

You are helping the user decide what to do with a phase-2 task that stopped
for a human. Arguments: $ARGUMENTS

1. Read `.bus/escalations/<task>.md`, `.bus/tasks/<task>.json`, the latest
   `.bus/review/<task>/round-<n>/` (verdict.json, decision.json) and
   `.bus/verify/<task>.json`. Look at the change itself with
   `git -C .worktrees/<task> diff "$(jq -r .base .bus/tasks/<task>.json)"`.
2. Explain in a few sentences why it stopped and what the realistic options
   are. Recommend one:
   - **accept**: the change is right and the escalation was caution (for
     example a sensitive area). Only possible when VERIFY passed. It is merged
     into `orchestra/run`.
   - **reject "<what to change>"**: the code is wrong in a way the agent can
     fix; the message goes to the agent and its retry budget is reset.
   - **retry ["<note>"]**: the task was BLOCKED by something outside the code
     (environment, config, a flaky tool) that is now fixed.
   - **amend-spec "<what changed>"**: the design was wrong. First edit the
     documents with the user: `docs/01-SRS.md`, `docs/06-test-plan.md`, the
     task's `docs/specs/<task>.md`, and `traceability.json` / `plan.json` if
     tests or tasks change. Then resolve; the engine re-runs the readiness
     check, re-freezes the design and restarts the task from scratch.
3. When the user agrees, run `orchestra resolve <task> <action> ["<msg>"]`
   with the Bash tool and show its output. Then remind them that
   `orchestra go` continues the run.
