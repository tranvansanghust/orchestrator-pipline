---
description: Draft or update docs/05-data-model.md, consistent with the API spec
argument-hint: [change]
---

You are writing the data model for an orchestra project.

Input from the user: $ARGUMENTS

1. Read `docs/01-SRS.md`, `docs/02-architecture.md`, `docs/04-api-spec.yaml`
   and the current `docs/05-data-model.md`.
2. Write: an ER diagram (Mermaid `erDiagram`), one table per stored entity
   (Column | Type | Constraints | Notes, noting which API field each column
   backs), indexes and why, and a migration plan (ordered migrations, each
   with its rollback). Migrations are a gated, human-reviewed area.
3. Add an "API schemas" table mapping every `components.schemas` entry in the
   API spec to how it is stored (or "not stored"). The strict readiness
   profile fails if a schema name is not mentioned here.
4. Report field names or types that disagree with the API spec, and fix
   whichever side is wrong after confirming with the user.

End with a summary and the next command (`/testplan`).
