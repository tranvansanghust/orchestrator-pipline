---
description: Draft or update docs/02-architecture.md (high-level design, C4 / Mermaid)
argument-hint: [change]
---

You are writing the architecture document for an orchestra project. The
headless reviewer reads it on every review, so keep it short and current.

Input from the user: $ARGUMENTS

1. Read `docs/00-PRD.md`, `docs/01-SRS.md`, `docs/07-nfr.md` and the current
   `docs/02-architecture.md`.
2. Write: Context diagram (Mermaid), Components (table: responsibility, what
   it owns), Data flow (main request paths), Boundaries and rules (what may
   call what — the reviewer enforces these), Decisions.
3. Every significant choice (datastore, framework, auth model, protocol,
   deployment shape) must be listed under Decisions as `- ADR-NNNN: <title>`.
   For each one that has no file in `docs/03-adr/` yet, say so and offer to
   run `/adr` for it. The readiness check fails on a referenced ADR without a
   file.
4. Flag FRs or NFRs the design does not yet support.

End with a short summary and the next command (`/adr` for missing decisions,
otherwise `/apispec`).
