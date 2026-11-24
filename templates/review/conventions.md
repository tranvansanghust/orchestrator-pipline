# Conventions

> Defaults included in every review pack when the project has no
> `docs/conventions.md`.

- Follow the existing style of the files being changed.
- Small functions, clear names, no commented-out code.
- Handle errors explicitly; no silent catch-all.
- No new dependency without a reason in the spec or an ADR.
- Tests are deterministic: no network, no sleeps, no order dependence.
