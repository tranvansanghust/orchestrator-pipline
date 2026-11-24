# Non-Functional Requirements

### NFR-1: Listing performance

| Metric | Target | How measured |
|---|---|---|
| `GET /posts` p95 latency | < 200 ms at 50 rps with 100k posts | k6 against the integration build |

### NFR-2: Password storage

| Metric | Target | How measured |
|---|---|---|
| Hash algorithm | bcrypt, cost ≥ 12 | `test/auth.register.test.ts` inspects the stored hash |
| Passwords in logs or responses | 0 occurrences | review rubric + log capture in tests |

### NFR-3: Observability

| Metric | Target | How measured |
|---|---|---|
| Structured logs | 100% of requests logged as JSON with `request_id`, status, duration | log capture in e2e test |
