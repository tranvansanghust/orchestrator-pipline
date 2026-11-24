# ADR-0002: Stateless JWT access tokens

- Status: accepted
- Date: 2026-11-25

## Context

The API is stateless and has no logout or revocation requirement this
release. Sessions in the database would add a table and a query per request.

## Decision

Issue HS256-signed JWTs with `sub` = user id and a 1-hour expiry. No refresh
tokens. The signing secret comes from the `JWT_SECRET` environment variable.

## Consequences

- No server-side revocation: a leaked token is valid until it expires.
- Adding logout later requires a denylist or refresh tokens (new ADR).
