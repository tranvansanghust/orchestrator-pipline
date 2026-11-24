---
description: Show phase-2 task states, requirement status and open escalations
---

1. Run `orchestra status` with the Bash tool.
2. Summarise in a few lines: how many tasks are done, which are running,
   blocked or escalated, and which requirements are accepted.
3. For each entry under "Needs a human", read `.bus/escalations/<task>.md` and
   explain in one or two sentences what is needed, then suggest the matching
   `/resolve` command.
