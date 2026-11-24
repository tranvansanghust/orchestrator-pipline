# Adapter interface

An adapter normalises one agent CLI behind four functions. Adding a CLI means
adding one file here — the engine never changes. All CLI-specific mess (flags,
output parsing, "done" detection) stays inside that one file.

Agents are declared statically in `orchestra.config.json`; the scheduler
matches them to tasks by skill. Several agents can share one adapter (e.g. glm
and deepseek both use `opencode` with different `model`s): an adapter is "how to
talk to a CLI", an agent is "a CLI + model + skills".

## The four functions

Each is called as `adapter_<fn> <agent> [args...]` — the agent name comes first,
and the adapter reads anything else it needs (model, flags) from the config via
`agent_field <agent> '<jq-path>'`. Adapters never parse JSON themselves.

| Function | Args (after `<agent>`) | Contract |
|---|---|---|
| `adapter_spawn` | — | Verify the CLI is present **and in the right mode**; return 0 when ready, non-zero otherwise. |
| `adapter_dispatch` | `<task-id> <spec-file> <workdir>` | Start the run in `workdir` and return immediately. |
| `adapter_wait` | `<task-id> [timeout-seconds]` | Block until the run finishes. 0 = done, 1 = failed, 124 = timeout. |
| `adapter_capability` | — | Print default skills, one per line. The agent's `skills` in the config override this. |

## Execution models (ADR-0006)

- **run-to-exit** (default): the CLI runs once and exits; "done" = process exit.
  No tmux. Use the `lib/adapter.sh` helpers `run_to_exit_dispatch` and
  `run_to_exit_wait`, which record `.bus/agents/<task>.{log,pid,exit}`.
  `mock`, `opencode` and `claude` work this way.
- **pane-parse**: a TUI-only CLI. `adapter_dispatch` sends keys to a tmux pane
  and `adapter_wait` parses the pane to detect completion (roadmap step 5).

`adapter_spawn` must verify the **mode**, not just that the binary exists: some
CLIs default to an interactive or disabled mode that never signals completion.

## Status

| Adapter | Status |
|---|---|
| `mock.sh` | Reference run-to-exit adapter; no network. Set `ORCHESTRA_MOCK_CMD` to script it. |
| `opencode.sh` | Implemented, verified against opencode 1.19.6 (`run --format json --auto`). |
| `claude.sh` | Implemented (`claude -p`), coding-agent role. |
| `deepseek.sh` | Stub — normally runs through the opencode adapter. |
| `kilo.sh` | Stub — TODO: verify non-interactive mode and "done" signal. |
| `zcode.sh` | Stub — TODO: verify dynamic-workflow mode (off by default) and "done" signal. |
