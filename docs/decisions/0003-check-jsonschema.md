# ADR-0003: Validate schemas with check-jsonschema

- Status: accepted
- Date: 2026-11-24

## Context

`jq` cannot validate JSON Schema. Candidates were `ajv-cli` (node) and
`check-jsonschema` (python).

## Decision

Use `check-jsonschema` (`pip install check-jsonschema` or
`brew install check-jsonschema`). All calls go through `lib/schema.sh`, so the
validator can be swapped in one place.

## Consequences

- Python becomes a runtime dependency of the engine.
- It also validates YAML instances, which covers the OpenAPI spec.
