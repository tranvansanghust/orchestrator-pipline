# orchestra

Công cụ điều phối coding tự động, cài một lần rồi dùng cho mọi project.

- **Pha 1 (thiết kế):** bạn làm việc với Claude Code TUI để soạn hồ sơ SDLC trong `docs/`, kèm `plan.json` và `traceability.json`.
- **Pha 2 (thực thi):** sau `orchestra go`, một daemon giao task cho các agent CLI (OpenCode/GLM-4.6, DeepSeek…). Mỗi task chạy trong một git worktree riêng. Máy chạy test/typecheck/build trước, qua rồi mới đến `claude -p` review. Chỗ nào không chắc chắn thì hệ thống kéo người về xử lý.

Thiết kế đầy đủ: [`ORCHESTRA-context.md`](ORCHESTRA-context.md). Các quyết định kỹ thuật của engine: [`docs/decisions/`](docs/decisions/).

> **Trạng thái: v0.1.0, mới có skeleton.** `orchestra help` và `orchestra version` đã chạy được. Các lệnh còn lại trả về exit code 3 (chưa implement).

## Yêu cầu

| Công cụ | Dùng cho |
|---|---|
| POSIX `sh`, `git`, `jq` | engine (macOS có sẵn) |
| `check-jsonschema` | validate schema (`brew install check-jsonschema`) |
| `tmux` | cockpit, pane cho agent |
| `claude` | pha 1 (TUI) và reviewer pha 2 (`claude -p`) |
| `opencode` | executor chính |
| `shellcheck`, `bats-core` | phát triển engine |

## Cài đặt

```sh
git clone <repo> ~/.orchestra
~/.orchestra/install.sh            # symlink vào ~/.local/bin (đổi bằng --prefix DIR)
orchestra help
```

Muốn nâng cấp, chạy `git pull` trong `~/.orchestra`: mọi project dùng engine này sẽ nhận bản mới.

## Cấu trúc

```
bin/orchestra     entrypoint: init | design | go | status | resolve | stop
lib/              các module (state machine, scheduler, pool, runner, review, escalation…)
adapters/         mỗi CLI một file, cùng một interface 4 hàm (xem adapters/README.md)
commands/         slash-command cho pha 1, `init` sẽ copy vào .claude/commands/
templates/        khung trống: docs/ 10 tầng + specs, config, plan, traceability; `init` copy sang project
examples/         blog-api: bộ hồ sơ pha 1 điền đủ, dùng làm mẫu và fixture cho test
profiles/         lite | standard | strict: những readiness check bắt buộc
schemas/          JSON Schema cho config, plan, traceability, task, verdict, escalation
test/             bats
```

Engine không chứa thông tin riêng của project nào. Mọi khác biệt giữa các project phải đi qua `orchestra.config.json` hoặc adapter.

## Phát triển

```sh
make lint      # shellcheck -s sh
make schemas   # schema hợp lệ + templates/examples khớp schema
make test      # bats test/
make check     # chạy cả ba
```

## Lộ trình

- [x] 0. Skeleton repo
- [ ] 1. Artifact nền: ~~schemas, templates docs/, traceability~~ (xong), readiness check
- [ ] 2. Runner VERIFY (`done_when`)
- [ ] 3. Review + context pack (`claude -p` → verdict)
- [ ] 4. Daemon end-to-end với 1 agent
- [ ] 5. Pool nhiều agent + worktree + integration build
- [ ] 6. Escalation UX: `/resolve`, dashboard, gates
- [ ] 7. Đóng gói: `orchestra init`, versioning, CI
