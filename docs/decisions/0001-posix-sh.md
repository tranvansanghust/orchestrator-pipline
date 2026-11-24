# ADR-0001: Engine is written in POSIX sh

- Status: accepted
- Date: 2026-11-24

## Context

The engine is installed once and used across many projects and machines.
macOS ships bash 3.2; users run zsh (oh-my-zsh) interactively. Depending on a
specific bash version would make installation fragile.

## Decision

All engine scripts use `#!/bin/sh` and POSIX syntax only. `local` is allowed
(supported by every common sh). Lint with `shellcheck -s sh`. Tests use bats,
which runs the scripts as external commands.

## Consequences

- No arrays: lists go through `jq` or newline-separated strings; state lives
  in JSON anyway.
- The user's interactive shell does not matter; `install.sh` only adds the
  PATH entry to `~/.zshrc` if needed.
