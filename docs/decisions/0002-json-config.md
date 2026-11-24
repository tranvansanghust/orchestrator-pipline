# ADR-0002: Machine-read files are JSON, read with jq

- Status: accepted
- Date: 2026-11-24

## Context

POSIX sh cannot parse structured data. `jq` ships with macOS; `yq` does not.

## Decision

Every file the engine reads or writes is JSON: `orchestra.config.json`,
`plan.json`, `traceability.json`, profiles, and everything under `.bus/`.
The only dependency for reading them is `jq`.

## Consequences

- The design doc's `orchestra.config.yaml` and `traceability.yaml` become
  `.json`.
- `docs/04-api-spec.yaml` stays YAML (standard OpenAPI, written by humans);
  it is validated by `check-jsonschema`, which reads YAML. If the engine later
  needs to read fields from it, revisit this decision.
