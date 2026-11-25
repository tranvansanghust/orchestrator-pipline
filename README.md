# orchestra

Công cụ điều phối coding tự động, cài một lần rồi dùng cho mọi project.

- **Pha 1 — thiết kế (người ⇄ Claude):** bạn làm việc với Claude Code để soạn bộ hồ sơ SDLC trong `docs/` (PRD, SRS, kiến trúc, ADR, OpenAPI, data model, test plan, task breakdown, review brief), kèm `plan.json` và `traceability.json`.
- **Pha 2 — thực thi (tự động):** `orchestra go` kiểm tra hồ sơ đã đủ chưa, đóng băng nó, rồi giao từng task cho các agent CLI (Claude, OpenCode/GLM, DeepSeek, ZCode…), chạy song song khi có nhiều agent. Mỗi task chạy trong một git worktree riêng. Máy chạy test/typecheck/build trước, đạt rồi mới đến Claude review hai lớp. Chỗ nào không chắc chắn thì dừng lại và chờ người.

Thiết kế gốc: [`ORCHESTRA-context.md`](ORCHESTRA-context.md). Mọi quyết định kỹ thuật: [`docs/decisions/`](docs/decisions/) (ADR-0001 → 0013).

> **Trạng thái: v0.3.0.** Chạy được trọn vòng: `init` → thiết kế với Claude → `go` (readiness, đóng băng, chạy song song, VERIFY, review hai lớp, merge) → `resolve` khi cần người → integration build, cho một repo hoặc một workspace nhiều repo. Đã kiểm chứng bằng 168 test offline (`make check`), cùng test online với Claude thật.

## Yêu cầu

| Công cụ | Dùng cho | Bắt buộc |
|---|---|---|
| POSIX `sh`, `git`, `jq` | engine | có (macOS có sẵn) |
| `check-jsonschema` | validate plan/config/verdict | có — `brew install check-jsonschema` hoặc `pipx install check-jsonschema` |
| `claude` (Claude Code) | pha 1, reviewer và confirmer ở pha 2 | có |
| ít nhất một agent CLI | viết code ở pha 2 | có — `claude`, `opencode`, hoặc ZCode |
| `tmux` | cockpit `orchestra design` | không (thiếu thì mở Claude ngay tại chỗ) |
| `redocly` hoặc `swagger-cli` | validate OpenAPI đầy đủ | không (thiếu thì kiểm nhẹ và báo NOTE) |

Chạy `orchestra doctor` để kiểm tra máy và project.

## Cài đặt

```sh
git clone <repo> ~/.orchestra
~/.orchestra/install.sh           # symlink vào ~/.local/bin (đổi bằng --prefix DIR)
orchestra doctor
```

Nâng cấp: `git -C ~/.orchestra pull`. Mọi project dùng engine này đều nhận bản mới; project ghim `orchestra_version`, lệch major thì engine cảnh báo.

## Từ con số 0 đến lúc chạy

```sh
cd my-project                     # một git repo, có ít nhất một commit
orchestra init                    # docs/ trống, orchestra.config.json, plan.json, .claude/commands/
```

**1. Sửa `orchestra.config.json`.** `init` đã điền sẵn `stack` theo project (node/ts, python, go, rust). Bạn chọn:
- `agents`: agent nào được dùng, mỗi agent có `adapter` (`claude`, `opencode`, `zcode`, `mock`), `model` và `skills`;
- `escalation.always_human`: các vùng luôn phải có người duyệt (`auth`, `payment`, `migration`…);
- `profile`: `lite` / `standard` / `strict` (độ chặt của readiness check).

**2. Thiết kế với Claude.**

```sh
orchestra design                  # tmux: Claude bên trái, dashboard bên phải
```

Trong Claude, chạy lần lượt:

```
/prd  /srs  /architect  /adr "…"  /apispec  /datamodel  /testplan  /breakdown  /plan  /handoff  /go
```

Mỗi lệnh ghi một tầng hồ sơ và kiểm tra nó khớp với các tầng khác. `/go` chạy readiness check, cùng bạn sửa các lỗ hổng, rồi đóng băng hồ sơ.

**3. Commit hồ sơ rồi chạy pha 2.**

```sh
git add docs plan.json traceability.json && git commit -m "design"
orchestra go                      # chạy tới khi xong hoặc cần người; Ctrl-C / orchestra stop để dừng
orchestra status --watch          # ở một terminal khác
```

`orchestra go` có thể chạy lại bất cứ lúc nào: nó tiếp tục từ chỗ dừng. Nếu bạn sửa hồ sơ sau khi đóng băng, nó liệt kê các file đã đổi và đòi `--refreeze`.

**4. Khi cần người.** Task bị BLOCKED/ESCALATED nằm trong `.bus/escalations/`. Các task khác vẫn chạy tiếp.

```sh
orchestra resolve T3              # mở Claude đã nạp sẵn ngữ cảnh của escalation
orchestra resolve T3 accept                     # merge nguyên trạng
orchestra resolve T3 reject "dùng hằng số"      # trả lại agent kèm lời nhắn
orchestra resolve T3 retry                      # vấn đề bên ngoài đã sửa xong
orchestra resolve T3 amend-spec "sửa FR-4"      # sau khi đã sửa hồ sơ
orchestra go                                    # chạy tiếp
```

**5. Lấy kết quả.** Toàn bộ code đã duyệt nằm trên nhánh `orchestra/run`. Bạn review rồi merge vào nhánh của mình. Engine **không bao giờ** đụng vào nhánh bạn đang làm và **không bao giờ** push.

## Workspace nhiều repo

Một project có thể gồm nhiều repo git nằm cạnh nhau, ví dụ `backend/` và `frontend/` (ADR-0013). Thư mục cha là repo `root`: nó chứa `docs/`, `plan.json`, config và các file chung như `docker-compose.yml` hay e2e. Mỗi repo con có `stack` riêng.

```sh
cd my-workspace                   # chứa backend/ và frontend/, mỗi thư mục là một repo git
orchestra init                    # tự nhận ra các repo con, git init thư mục cha, gitignore các repo con
git add -A && git commit -m "orchestra workspace"
```

```json
"repos": {
  "backend":  { "path": "backend",  "stack": { "language": "go", "test": "go test ./...", "test_one": "go test {files}" } },
  "frontend": { "path": "frontend", "stack": { "language": "typescript", "test": "npm test", "test_one": "npx vitest run {files}" } }
}
```

- Task trong `plan.json` ghi các repo nó được sửa ở `repos` (mặc định `["root"]`). `scope` và `tests_pass` tính từ thư mục cha, ví dụ `backend/internal/...`.
- Mỗi task có một worktree mô phỏng lại workspace: repo được giao được checkout trên nhánh `orchestra/<task>`, các repo còn lại là bản chỉ đọc. Sửa vào bản chỉ đọc thì thay đổi bị huỷ và lượt đó tính là VERIFY fail.
- VERIFY chạy test của từng repo bằng `stack` của repo đó. Reviewer nhận một diff gộp. Merge diễn ra ở mọi repo của task, hoặc không repo nào. `stack.integration` của root chạy trên `.worktrees/_run`, nơi các repo nằm cạnh nhau.
- Kết quả nằm trên nhánh `orchestra/run` của **từng repo**.
- Chạy `orchestra` ở đâu trong workspace cũng được, kể cả bên trong một repo con.

Ví dụ chạy được ngay: `examples/workspace/make-demo.sh /tmp/demo` dựng một workspace gồm `api/` và `web/`.

## Lệnh

| Lệnh | Việc |
|---|---|
| `orchestra init [--force]` | scaffold vào project hiện tại |
| `orchestra design` | cockpit tmux (Claude + dashboard) |
| `orchestra go [--profile P] [--refreeze] [--no-run]` | readiness → đóng băng → chạy pha 2 (tiếp tục nếu đã chạy dở) |
| `orchestra status [--watch]` | trạng thái task, FR, hộp thư cần người |
| `orchestra resolve <task> [action] [msg]` | xử lý task bị BLOCKED/ESCALATED |
| `orchestra stop` | dừng run sau bước hiện tại |
| `orchestra doctor` | kiểm tra dependency, agent và project |

Exit code: `0` xong (hoặc đã dừng), `1` lỗi, `2` sai cú pháp, `4` có task cần người.

## Cách pha 2 giữ an toàn

- **Máy kiểm trước, Claude review sau.** Agent không tự tuyên bố "xong"; runner chạy `done_when` thật.
- **Review hai lớp.** Reviewer (không có tool, chỉ đọc context pack) ra verdict có bằng chứng gắn nguồn. Confirmer kiểm lại mọi ACCEPT và chỉ được hạ mức tin cậy, không bao giờ nâng.
- **Luật cứng cho ACCEPT:** confidence thấp, concern high/critical, file ngoài `scope`, vùng `always_human` hay `migration`/`delete` → ESCALATE. Reviewer cần người (`needs_human`) → ESCALATE.
- **Nội dung agent viết** (diff, test) được bọc trong `<untrusted-data>` với id ngẫu nhiên.
- **Tích hợp có kiểm tra:** trước khi merge, nhánh task được cập nhật theo `orchestra/run` và chạy lại VERIFY nếu có thay đổi.
- **Có trần ở mọi nơi:** `max_verify_rounds`, `max_reject_rounds`, `agent_timeout_s`, `review.max_budget_usd`, `review.max_pack_bytes`.

## Agent

| Adapter | Gọi | Ghi chú |
|---|---|---|
| `claude` | `claude -p` | |
| `opencode` | `opencode run --format json --auto` | GLM, DeepSeek… qua trường `model` |
| `zcode` | `zcode -p --cwd --json` | tìm CLI qua `ORCHESTRA_ZCODE_BIN`, PATH, hoặc ZCode.app |
| `mock` | không gọi mạng | dùng cho test |
| `kilo`, `deepseek` | stub | chưa kiểm chứng |

Thêm agent mới = viết một file `adapters/<tên>.sh` với 4 hàm (xem [`adapters/README.md`](adapters/README.md)), engine không cần sửa.

## Cấu trúc

```
bin/orchestra     entrypoint
lib/              state machine, scheduler, pool, runner, review, escalation, daemon…
adapters/         mỗi CLI một file, cùng interface 4 hàm
commands/         slash command pha 1 (init copy vào .claude/commands/)
templates/        khung docs/, config, plan, traceability, rubric, prompt reviewer
profiles/         lite | standard | strict
schemas/          JSON Schema: config, plan, traceability, task, verify, verdict, confirmation, decision
examples/         blog-api: bộ hồ sơ pha 1 điền đủ; workspace: ví dụ nhiều repo (make-demo.sh)
test/             bats
```

Trạng thái lúc chạy nằm trong `.bus/` của project (gitignore): task, prompt, log của agent, verify report, các vòng review, escalation, `log.jsonl`. Không có gì chỉ nằm trong bộ nhớ.

## Phát triển

```sh
make check                              # shellcheck + schema + toàn bộ test offline (~5 phút)
ORCHESTRA_ONLINE=1 bats test/*_online.bats   # gọi Claude/opencode thật, tốn tiền API
```

CI: `.github/workflows/check.yml` chạy `make check` trên Linux và macOS.

## Chưa làm

- Adapter `kilo` (chưa có CLI để kiểm chứng) và `deepseek` dạng CLI riêng (hiện chạy qua opencode).
- Agentic review (cho reviewer đọc file) cho task phức tạp.
- Pane-parse adapter cho CLI chỉ có TUI.
- Pha 1 sinh sẵn code test trước khi `go` (hiện agent viết test theo test plan).
