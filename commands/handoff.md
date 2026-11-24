---
description: Write docs/09-review-brief.md, the design intent the headless reviewer protects
---

You are writing the review brief. The phase-2 reviewer is a headless Claude
with no memory of this conversation and no tools: this file, the architecture
and the rubric are everything it knows about *why* the design is the way it is.
It is included in every review, so keep it under a page.

1. Re-read all of `docs/` and recall the decisions and worries from this
   session.
2. Write `docs/09-review-brief.md`:
   - **Intent**: what the system is for, in three sentences;
   - **Invariants**: things that must always hold (violating one is a REJECT),
     stated so a diff can be checked against them;
   - **Red lines**: changes that must go to a human even if tests pass;
   - **Known risks**: where mistakes are likely and what they look like in code;
   - **Out of scope**: changes the reviewer should reject as scope creep.
3. Prefer concrete, checkable statements ("`author_id` always comes from the
   verified token") over general advice ("be secure").

End with the brief's length and the next command (`/go`).
