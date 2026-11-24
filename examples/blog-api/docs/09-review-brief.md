# Review Brief

## Intent

A minimal, boring, correct blog backend. Correct auth matters more than
features; anything clever in auth is a smell.

## Invariants

- Password hashes never leave the model layer — not in responses, logs or errors.
- `author_id` always comes from the verified token, never from the request body.
- Routes do not query the database directly (02-architecture.md).
- Response shapes match 04-api-spec.yaml exactly.
- Login failures are indistinguishable whether the email exists or not.

## Red lines

- Any change to token signing, verification or expiry.
- Any migration that alters or drops an existing column.
- New dependencies in the auth path.

## Known risks

- Pagination on `created_at` alone skips or repeats rows with equal
  timestamps — the cursor must include `id`.
- JWT libraries that accept `alg: none` or algorithm confusion by default.
- Timing differences between "unknown email" and "wrong password".

## Out of scope

Editing/deleting posts, comments, refresh tokens, password reset, rate
limiting. Reject diffs that add them.
