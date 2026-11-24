# ADR-0001: PostgreSQL as the only datastore

- Status: accepted
- Date: 2026-11-25

## Context

We need durable storage for users and posts, a unique constraint on email,
and ordered pagination. Traffic is modest (NFR-1).

## Decision

Use a single PostgreSQL instance for all data. No cache layer in this release.

## Consequences

- Case-insensitive uniqueness via a unique index on `lower(email)`.
- Keyset pagination on `(created_at, id)` meets NFR-1 without a cache.
- Migrations become a gated area (`always_human: migration`).
