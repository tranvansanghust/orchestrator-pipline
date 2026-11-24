# Software Requirements Specification

## Scope

A JSON HTTP API for users and posts, serving goals 1–3 of 00-PRD.md.
Non-functional requirements are in 07-nfr.md.

## Functional requirements

### FR-1: Register with email and password

A visitor creates an account with an email and a password.

- Priority: must
- Acceptance: `POST /auth/register` with a valid body → 201 and the user
  (never the password or its hash); duplicate email (case-insensitive) → 409;
  invalid email or password shorter than 12 characters → 422.

### FR-2: Log in and receive a JWT

A registered user exchanges email and password for an access token.

- Priority: must
- Acceptance: `POST /auth/login` with correct credentials → 200 and a JWT
  valid for 1 hour; wrong password or unknown email → 401 with an identical
  response body (no account enumeration).

### FR-3: Authenticated user creates a post

- Priority: must
- Acceptance: `POST /posts` with a valid bearer token → 201 and the post,
  author taken from the token; missing or expired token → 401; empty title or
  title longer than 200 characters → 422.

### FR-4: Anyone lists posts, newest first, paginated

- Priority: must
- Acceptance: `GET /posts` → 200 with posts ordered by `created_at` desc,
  default page size 20, `limit` up to 50 (larger → 422); following
  `next_cursor` visits every post exactly once.

## Constraints and assumptions

- Single region, single PostgreSQL instance (ADR-0001).
- Stateless auth with short-lived JWTs (ADR-0002).
