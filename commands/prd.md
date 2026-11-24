---
description: Draft or update docs/00-PRD.md (what we build and why)
argument-hint: [product idea or change]
---

You are helping the user write the Product Requirements Document for an
orchestra project. Phase 1 artifacts are read by humans and by machines, so
they must be precise.

Input from the user: $ARGUMENTS

1. Read `docs/00-PRD.md` (it may still be the blank template; keep its
   section structure and the guidance in the HTML comments).
2. If the idea is vague, ask at most three short questions that change what
   gets built (users, the one problem that matters, what is out of scope).
   Otherwise proceed.
3. Write the PRD: Problem, Users, Goals (each measurable), Non-goals (explicit,
   so nobody builds them), Success metrics (a table with real targets), Open
   questions. No implementation detail.
4. If `docs/01-SRS.md` already has requirements, list any that no longer
   follow from the PRD, or PRD goals with no requirement yet.

End with a three-line summary of what changed and the suggested next command
(`/srs`).
