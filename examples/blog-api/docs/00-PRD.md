# Product Requirements

## Problem

Small teams want a minimal backend for a blog without adopting a full CMS.
Today they hand-roll auth and posting each time, and get auth wrong.

## Users

- **Writer** — registers, logs in, publishes posts.
- **Reader** — anonymous, browses posts.

## Goals

1. A writer goes from sign-up to first published post with three API calls.
2. Readers can page through every post without gaps or duplicates.
3. Auth follows current password-storage practice out of the box.

## Non-goals

- Comments, likes, tags, media upload.
- Editing or deleting posts (next release).
- Password reset, OAuth, email verification.
- Any frontend.

## Success metrics

| Metric | Target |
|---|---|
| Calls from sign-up to first post | 3 |
| p95 latency of `GET /posts` | < 200 ms at 50 rps |
| Critical auth findings in review | 0 |

## Open questions

- None blocking this release.
