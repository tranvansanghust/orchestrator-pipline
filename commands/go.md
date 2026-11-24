---
description: Run the readiness check, approve and freeze the design; fix gaps with the user
argument-hint: [--profile lite|standard|strict]
---

You are closing phase 1.

1. Run `orchestra go --no-run $ARGUMENTS` with the Bash tool. It runs the
   design readiness check and, if every required check passes, marks
   `plan.json` approved and freezes `docs/`, `plan.json` and
   `traceability.json` (hashes in `.bus/frozen.json`).
2. If checks fail, go through the listed gaps one by one with the user and
   fix them in the documents (re-running the matching command, e.g. `/srs` or
   `/testplan`, when a gap needs real design work). Re-run step 1 until it
   passes. If the design was already frozen and changed since, add
   `--refreeze` after confirming the user wants the changes.
3. When it passes, suggest committing `docs/`, `plan.json` and
   `traceability.json`, then tell the user to start phase 2 in a terminal or
   tmux pane with `orchestra go` (it runs until the plan is done or needs a
   human; `orchestra status` shows progress, `orchestra stop` pauses it).

Do not start the phase-2 run yourself: it is long-running and belongs outside
this session.
