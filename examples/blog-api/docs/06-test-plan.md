# Test Plan

## Strategy

- Integration tests with vitest + supertest against a throwaway PostgreSQL
  (testcontainers); no mocked database.
- Each test file owns its data and truncates tables before each test.
- `npm run test:e2e` runs the full flow (register → login → post → list) for
  milestone integration builds.

## Definition of done

A task is done when every file in its `done_when.tests_pass` passes, plus
typecheck/build when its `done_when` asks for them — run by the engine, not
claimed by the agent.

## Coverage by requirement

### FR-1

- File: `test/user.model.test.ts`
  - Happy path: insert and read back a user; `created_at` set.
  - Edge / adversarial: duplicate email differing only in case is rejected;
    `password_hash` is not in the default select.
- File: `test/auth.register.test.ts`
  - Happy path: 201, body matches `User`, no `password`/`password_hash`.
  - Edge / adversarial: duplicate → 409; malformed email → 422; 11-char
    password → 422; extra fields rejected; stored hash is bcrypt cost ≥ 12.

### FR-2

- File: `test/auth.login.test.ts`
  - Happy path: 200, token verifies, `sub` = user id, `exp` ≈ now + 3600.
  - Edge / adversarial: wrong password and unknown email return identical
    401 bodies; token signed with another secret is rejected by the
    middleware; expired token rejected; `alg: none` rejected.

### FR-3

- File: `test/posts.create.test.ts`
  - Happy path: 201, `author_id` from the token, not from the body.
  - Edge / adversarial: no token → 401; expired → 401; `author_id` in body
    ignored or rejected; empty title → 422; 201-char title → 422.

### FR-4

- File: `test/posts.list.test.ts`
  - Happy path: newest first, default 20, `next_cursor` null on last page.
  - Edge / adversarial: `limit=51` → 422; garbage cursor → 422; posts with
    equal `created_at` are neither skipped nor repeated across pages;
    public (no token needed).
