---
description: Draft or update docs/04-api-spec.yaml (real OpenAPI 3.1, the cross-task contract)
argument-hint: [change]
---

You are writing the API contract for an orchestra project. It is real,
machine-readable OpenAPI: coding agents implement against it, the reviewer
checks diffs against it, and it must stay consistent with the data model.

Input from the user: $ARGUMENTS

1. Read `docs/01-SRS.md`, `docs/02-architecture.md`, `docs/05-data-model.md`
   and the current `docs/04-api-spec.yaml`.
2. Write valid OpenAPI 3.1 YAML: every endpoint an FR needs, with an
   `operationId`, request schema, every response status the FR's acceptance
   line mentions (including errors), and shared shapes under
   `components.schemas`. Use `additionalProperties: false` on request bodies.
3. Validate it if a validator is available (`redocly lint` or
   `swagger-cli validate`); otherwise at least check it parses as YAML and
   has `openapi: 3.x` and `paths:`.
4. Report:
   - FRs with no endpoint, endpoints serving no FR;
   - field names or types that differ from `docs/05-data-model.md`;
   - every `components.schemas` name, which `05-data-model.md` must mention
     (strict profile checks this).

End with a summary of endpoints added or changed and the next command
(`/datamodel`).
