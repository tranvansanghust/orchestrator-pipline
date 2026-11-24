# Adapter interface

An adapter normalises one agent CLI behind four functions. Adding a CLI means
adding one file here — the engine never changes. All CLI-specific mess
(output parsing, "done" detection) stays inside that one file.

Adapters share function names, so `lib/pool.sh` always sources an adapter in
a subshell. An adapter may use the helpers from `lib/common.sh`.

| Function | Args | Contract |
|---|---|---|
| `adapter_spawn` | `<agent> <pane> <workdir>` | Create the pane and start the CLI (or prepare it for headless runs). Return 0 when ready. |
| `adapter_dispatch` | `<agent> <task-id> <spec-file> <workdir>` | Hand the task spec to the agent and return immediately. |
| `adapter_wait` | `<agent> <task-id> [timeout-seconds]` | Block until the agent finishes. Exit 0 = finished, 1 = agent failed, 124 = timeout. |
| `adapter_capability` | `<agent>` | Print default skills, one per line. `skills` in the project config overrides this. |

`<agent>` is the `name` field of an entry in `orchestra.config.json`; the
adapter reads anything else it needs (model, flags) from that entry.

## Status

| Adapter | Status |
|---|---|
| `opencode.sh` | Stub — `opencode run` headless confirmed, to implement first |
| `claude.sh` | Stub — `claude -p` headless, to implement first |
| `deepseek.sh` | Stub — normally runs through the opencode adapter |
| `kilo.sh` | Stub — TODO: verify non-interactive mode and "done" signal |
| `zcode.sh` | Stub — TODO: verify non-interactive mode and "done" signal |
