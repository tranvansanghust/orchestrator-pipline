# SRS

The workspace has two repos: `api/` (data and logic) and `web/` (rendering).
The web code reads the API's shell functions directly (`../api/src/...`).

### FR-1: Count open todos

- Acceptance: `open_count` in `api/src/count.sh` prints the number of lines in
  `api/data/todos.txt` that do not start with `[x]`.

### FR-2: Header shows the count

- Acceptance: `header` in `web/src/header.sh` prints `Todos (<n> open)`, with
  `<n>` from the API's `open_count`.
