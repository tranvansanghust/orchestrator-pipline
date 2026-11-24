---
description: Record an architecture decision in docs/03-adr/ (Nygard format)
argument-hint: <decision>
---

You are recording one Architecture Decision Record.

Decision to record: $ARGUMENTS

1. List `docs/03-adr/` and pick the next free number `NNNN` (four digits;
   0000 is the template).
2. Create `docs/03-adr/NNNN-<short-slug>.md` from
   `docs/03-adr/0000-template.md`: title `# ADR-NNNN: <title>`, Status, Date
   (today), Context (the forces, why decide now), Decision (full sentences),
   Consequences (what gets easier, harder, newly required). Include the
   alternatives that were rejected and why.
3. Never edit the decision of an accepted ADR. If this one replaces an older
   one, set the old ADR's status to `superseded by ADR-NNNN` and say so here.
4. Make sure `docs/02-architecture.md` lists it under Decisions as
   `- ADR-NNNN: <title>`; add the line if missing.

End with the file path and one sentence on the decision.
