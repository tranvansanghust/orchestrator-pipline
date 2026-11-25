# Test plan

Plain `sh` tests: each file exits non-zero on the first failed assertion.
`e2e.sh` at the workspace root runs both repos' tests for the integration
build.

### FR-1

- File: `api/test/count.sh`
  - Happy path: two open and one done todo → `2`.
  - Edge: empty file → `0`; a line `[x]` alone counts as done.

### FR-2

- File: `web/test/header.sh`
  - Happy path: with the seeded data → `Todos (2 open)`.
  - Edge: no open todos → `Todos (0 open)`.
