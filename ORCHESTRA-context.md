# ORCHESTRA — Context Handoff để build repo

> Copy toàn bộ file này vào Claude Code để bắt đầu build repo.

## Mục tiêu dự án
Xây một **repo công cụ tái dùng** điều phối việc coding tự động: con người ngồi với Claude Code hoàn thiện hồ sơ thiết kế chuẩn SDLC, nhấn `/go`, rồi một daemon tự spawn dàn agent CLI (GLM-4.6, DeepSeek, Kilo, zcode qua OpenCode/các CLI) để code–test–build; Claude headless review từng output; hệ thống kéo người về TUI khi không chắc chắn. Đóng gói để `cài một lần — apply mọi project`.

> Lưu ý thực tế: model coding của Z.ai hiện là **GLM-4.6** (không phải "GLM-5.2"). Executor chính là **OpenCode** (`opencode run` headless đã xác nhận). Kilo/zcode: CẦN KIỂM CHỨNG có chế độ non-interactive + cách báo "hoàn thành" trước khi đưa vào pool — đây là rủi ro khả thi hàng đầu.

---

## Triết lý cốt lõi
1. **Hai pha tách bạch**, ranh giới là artifact (`plan.json` + `docs/`): Pha 1 (người ⇄ Claude TUI) ĐẺ ra, Pha 2 (tự động) TIÊU THỤ.
2. **Engine bất biến / Project state riêng**: mọi khác biệt giữa project đi qua **config** hoặc **adapter**, không bao giờ hardcode vào engine.
3. **Hai lớp kiểm tra**: VERIFY = máy (test/build, khách quan, rẻ, chạy trước) → REVIEW = Claude (logic/security/edge, chỉ chạy khi máy đã xanh).
4. **"Không chắc" luôn nghiêng về DỪNG**, không nghiêng về ĐI. Verdict có 3 nhánh, không nhị phân.
5. **Context cho reviewer headless không đến từ trí nhớ phiên mà từ artifact**: pha 1 kết tinh thiết kế thành file, pha 2 dựng lại context pack mỗi lần review.

---

## KIẾN TRÚC TỔNG THỂ

### Hai pha
```
PHA 1 — DESIGN (người ⇄ Claude TUI, tương tác)
  slash-commands: /prd /srs /architect /adr /datamodel /apispec
                  /testplan /breakdown /plan /handoff
  → sinh docs/ (hồ sơ chuẩn) + plan.json + traceability.yaml
  /go → DESIGN READINESS CHECK → đóng băng → kích pha 2

PHA 2 — EXECUTE (tự động; brain = claude -p headless, KHÔNG TUI)
  SCHEDULE → SPAWN agents → CODE → VERIFY(máy) → REVIEW(Claude)
  → MERGE → mở khóa task phụ thuộc
  ESCALATE → kéo người về TUI / inbox / hard gate
```

### Ba lớp
```
CONTROL   : Claude planner(TUI) + reviewer(headless); daemon state machine + scheduler + escalation
MESSAGE   : .bus/ mailbox JSON + tmux signals (wait-for / send-keys)
EXECUTION : pool agent động (glm·deepseek·kilo·zcode); mỗi task 1 git worktree, verify cô lập
```
Lý do tách lớp: thay agent / transport / brain mà không đụng phần còn lại.

### Layout tmux
```
p0 claude TUI (cockpit pha 1 / nơi escalate kéo về)   | p1 agent-A (glm)
p2 agent-B (deepseek)                                  | p3 watcher (log + dashboard escalation)
```
Agents spawn động theo skill/tải. Dùng TÊN pane ổn định (vd dev:main.1), không dùng index trôi.

---

## VÒNG ĐỜI TASK (state machine)
```
DRAFT → DISPATCHED → IN_PROGRESS → SUBMITTED
  → VERIFY (máy: test + typecheck + build)
       ├─ fail → agent sửa (≤ max_reject_rounds) → BLOCKED nếu vượt
       └─ pass → REVIEW (Claude headless)
                   ├─ ACCEPT   → MERGED → DONE (mở khóa task phụ thuộc)
                   ├─ REJECT   → sinh v2 (kèm feedback) → DRAFT
                   └─ ESCALATE → kéo người vào
```
Mọi transition chỉ theo cạnh hợp lệ (guard). Mọi transition append vào `.bus/log.jsonl` (audit).

---

## PHA 1 — HỒ SƠ THIẾT KẾ CHUẨN SDLC (output bắt buộc)

Pha 1 phải đẻ bộ hồ sơ vừa-cho-người vừa-cho-máy:
```
docs/
├── 00-PRD.md            # Product Requirements (what & why)
├── 01-SRS.md            # Software Requirements Spec: FR/NFR có ID (vd FR-03)
├── 02-architecture.md   # High-level design (C4 / 4+1), components, data flow, ranh giới
├── 03-adr/              # Architecture Decision Records (Nygard format), mỗi quyết định 1 file
├── 04-api-spec.yaml     # OpenAPI THẬT (máy đọc được) — là CONTRACT liên-task
├── 05-data-model.md     # ERD / schema / migration plan
├── 06-test-plan.md      # chiến lược test + traceability tới FR; định nghĩa "done"
├── 07-nfr.md            # security/perf/scale/observability — tiêu chí ĐO ĐƯỢC
├── 08-task-breakdown.md # WBS → ánh xạ 1-1 sang plan.json
└── 09-review-brief.md   # "linh hồn thiết kế" cho Claude reviewer headless
```

### Slash-commands pha 1 (mỗi lệnh ghi artifact + kiểm nhất quán với tầng trên)
```
/prd /srs /architect /adr "..." /datamodel /apispec /testplan /breakdown
/plan     → kết tinh thành plan.json
/handoff  → sinh 09-review-brief.md
/go       → chạy READINESS CHECK → đóng băng docs/ → kích pha 2
```
Giá trị của Claude-TUI ở pha 1: giữ hồ sơ KHÔNG mâu thuẫn giữa các tầng (vd /breakdown phải phủ hết FR trong SRS; /testplan phải có test cho mọi FR).

### DESIGN READINESS CHECK (chặn /go nếu chưa đạt)
```
☐ Mọi FR trong SRS có ≥1 task map tới        (coverage)
☐ Mọi task có ≥1 acceptance test             (testability)
☐ Mọi quyết định lớn có ADR                  (rationale)
☐ api-spec.yaml valid OpenAPI                (contract đúng cú pháp)
☐ data-model nhất quán với api-spec          (không lệch field)
☐ NFR có tiêu chí đo được                    (verifiable)
☐ review-brief tồn tại                       (handoff sẵn sàng)
✗ thiếu bất kỳ → chặn /go + liệt kê lỗ hổng
```
Mức nặng-nhẹ co giãn theo profile: `/go --profile lite|standard|strict`.

---

## TRACEABILITY — xương sống
Mọi requirement truy vết xuôi-ngược: Requirement → Task → Test → Code → Review.
```yaml
# traceability.yaml (máy cập nhật status khi test xanh)
FR-03:
  desc: "User login with email+password returns JWT"
  tasks: [T3]
  tests: [test/login.test.ts]
  acceptance: "POST /login → 200 + valid JWT; sai pass → 401"
  status: implemented
```

---

## plan.json — hợp đồng bàn giao pha 1 → pha 2
```json
{
  "goal": "blog API",
  "approved": true,
  "orchestra_version": "1.0",
  "build": { "cmd": "npm run build", "test": "npm test", "cwd": "." },
  "tasks": [
    { "id": "T1", "desc": "User model + migration", "deps": [], "skill": "backend",
      "spec_file": ".bus/specs/T1.md", "tests": ["test/user.model.test.ts"],
      "done_when": { "tests_pass": ["test/user.model.test.ts"], "typecheck": true } },
    { "id": "T3", "desc": "Login + JWT", "deps": ["T1"], "skill": "backend",
      "tests": ["test/login.test.ts"],
      "done_when": { "tests_pass": ["test/login.test.ts"] } }
  ]
}
```
`done_when` khiến pha 2 tự-kiểm-tra được không cần người (agent không tự phán "xong"; runner chạy test thật).

---

## PHA 2 — VÒNG LẶP THỰC THI
```
loop đến khi DAG cạn:
  1. SCHEDULE — chọn task deps đã xong → spawn/tái dùng agent theo skill
  2. CODE     — agent đọc spec+test → viết code (trong git worktree riêng)
  3. VERIFY   — runner chạy done_when (test/typecheck/build)
                ├─ fail → trả lỗi cho agent → sửa (≤ N vòng) → BLOCKED nếu quá
                └─ pass → REVIEW
  4. REVIEW   — claude -p đọc context pack → ACCEPT / REJECT / ESCALATE
  5. MERGE    — accept → commit vào branch task; CẬP NHẬT contract; mở khóa phụ thuộc
  6. GATE     — hành động phá hủy (push/deploy/xoá/migration) → dừng chờ người
```
Integration build local chạy sau mỗi milestone (build thật + smoke test + chạy dev server + health check) trong sandbox/pane riêng.

---

## CONTEXT CHO REVIEWER HEADLESS (giải bài toán "đủ context")
Claude pha 2 stateless → mỗi review DỰNG LẠI context pack từ artifact pha 1:
```
pack = [cố định: rubric.md + review-brief + 02-architecture + conventions.md]
     + [động:   specs/Tn + contracts/deps(api-spec) + diff(Tn) + verify-report]
     + [nếu v2: review trước + yêu cầu sửa]
     → claude -p --output-format json → verdict
```
Liên-task dựa vào **contract** (chữ ký hàm/shape/type từ api-spec), KHÔNG nhồi cả code.
Khi diff tham chiếu ngoài phạm vi: dùng dependency-closure diff (rẻ) → nâng lên agentic review (cho Claude quyền đọc file) cho task phức tạp.
Ngân sách context, thứ tự ưu tiên khi cắt: rubric > brief > spec+test > diff > contracts deps > conventions. Diff & test bất khả xâm phạm.
**Contract drift là rủi ro:** cập nhật `contracts/*.md` (hoặc api-spec) là BƯỚC BẮT BUỘC của MERGE, không tùy chọn. Integration build thật là lưới bắt lỗi tích hợp mà review-dựa-contract bỏ sót.

---

## ESCALATION — đường về người
```
verdict ∈ { ACCEPT, REJECT, ESCALATE }

Reviewer trả kèm: confidence, concerns[severity], needs_human, question_for_human

ESCALATE (trigger KÉP) khi:
  • Claude tự thú: confidence < threshold (vd 0.75) HOẶC concern high/critical
  • Luật cứng hệ thống (bất kể confidence):
      - vùng always_human: auth/payment/crypto/migration/xoá dữ liệu
      - diff lớn bất thường so với spec
      - đã REJECT ≥ K vòng (lặp = dấu hiệu SPEC sai, không phải code)
      - verify máy xanh NHƯNG reviewer vẫn thấy mùi (mâu thuẫn hai lớp)
      - task trong allowlist "luôn cần người"

3 KÊNH đưa về:
  (a) INBOX async   — ghi .bus/escalations/Tn.md; treo task này, DAG chạy tiếp task khác
  (b) TUI HANDOFF   — mở pane Claude-TUI đã NẠP SẴN context pack của đúng task;
                      kéo con trỏ người tới (tmux select-pane); người ⇄ Claude bàn trực tiếp
  (c) HARD GATE     — vùng critical: dừng nhánh phụ thuộc, chờ người

/resolve Tn accept
/resolve Tn reject "..."
/resolve Tn amend-spec "..."   → VÁ NGƯỢC về hồ sơ:
    cập nhật 01-SRS (thêm FR) + 06-test-plan (thêm test) + traceability.yaml → re-dispatch Tn
```
Nguyên tắc: khi vắng người, TUYỆT ĐỐI không auto-ACCEPT lúc ESCALATE — task treo inbox, phần còn lại tiếp tục. Escalate chỉ chặn chính nó + nhánh phụ thuộc. Mỗi escalation làm giàu hồ sơ → bớt escalate lần sau. Mọi escalation vào audit log.
Dashboard escalation hiển thị ở pane watcher (Tn, area, confidence, lý do, tuổi, [TUI]/[GATE]).

---

## ĐÓNG GÓI REPO (khả năng tái dùng)

### Tách bạch
```
ENGINE (repo orchestra, bất biến)   | PROJECT STATE (trong từng dự án)
lib/ bin/ commands/ templates/      | docs/ (commit) · orchestra.config.yaml (commit)
adapters/ profiles/ schemas/ test/  | .bus/ (gitignore, ephemeral) · code
```

### Cấu trúc engine
```
orchestra/
├── install.sh                 # --link symlink PATH / clone+alias / docker
├── bin/orchestra              # entrypoint: init|design|go|status|resolve|stop
├── lib/  statemachine.sh scheduler.sh pool.sh runner.sh review.sh
│         escalation.sh tmux.sh bus.sh
├── commands/  (prd…go…resolve…status).md   # copy vào .claude/commands/
├── templates/ docs/  traceability.yaml  plan.schema.json  orchestra.config.yaml
├── adapters/  opencode.sh claude.sh deepseek.sh kilo.sh zcode.sh
├── profiles/  lite.yaml standard.yaml strict.yaml
├── schemas/   verdict/task/escalation JSON Schema
├── test/      (bats/shunit2 cho chính engine)
└── VERSION
```

### Hai trừu tượng làm nên tái dùng

1) **ADAPTER** — chuẩn hóa mọi CLI về 1 interface (thêm CLI = 1 file, KHÔNG đụng engine):
```bash
adapter_spawn()      # tạo pane + chạy CLI headless
adapter_dispatch()   # nhận task spec, bắn vào agent, trả về ngay
adapter_wait()       # cách biết "hoàn thành" (tmux wait-for / parse output)
adapter_capability() # skills để scheduler khớp
```
CLI nào chỉ có TUI không-signal → adapter của nó tự parse để biết "xong"; độ bẩn bị cô lập trong đúng 1 file.

2) **CONFIG** — khai báo project, không sửa code:
```yaml
project: blog-api
profile: standard            # lite|standard|strict
orchestra_version: "1.0"     # ghim engine tương thích (semver)
stack:
  language: typescript
  build: "npm run build"
  test: "npm test"
  typecheck: "tsc --noEmit"
  integration: "npm run test:e2e"
brain:
  reviewer: "claude -p --output-format json"
  planner:  "claude"
agents:
  - { name: glm,      adapter: opencode, model: "glm/glm-4.6",            skills: [backend, api] }
  - { name: deepseek, adapter: opencode, model: "deepseek/deepseek-chat", skills: [algo, refactor] }
  - { name: kilo,     adapter: kilo,     skills: [frontend, ui] }
escalation:
  confidence_threshold: 0.75
  always_human: [auth, payment, migration]
  max_reject_rounds: 3
vcs:
  strategy: worktree
  gate: [push, deploy]
```

### Apply sang project khác: `orchestra init` (chạy trong thư mục project bất kỳ)
```
1. phát hiện stack (package.json/pyproject/go.mod…)
2. copy templates/docs/ → ./docs/ (khung trống)
3. copy config mẫu → ./orchestra.config.yaml (điền sẵn stack đoán được)
4. copy commands/ → ./.claude/commands/
5. tạo .bus/ + .gitignore (.bus/, .worktrees/)
6. in next step: "chạy orchestra design"
```

### Cài engine 1 lần, mọi project trỏ tới qua $PATH
`git pull` trong ~/.orchestra → tất cả project hưởng nâng cấp.

### Versioning (chống "nâng engine làm vỡ project cũ")
Project ghim `orchestra_version`; engine so với VERSION: lệch major → cảnh báo + hướng dẫn migrate. Semver: major = đổi schema config/plan; minor = thêm tính năng; patch = sửa lỗi.

### Override có kiểm soát
Project đặt `docs/rubric.md` riêng → engine ưu tiên bản project, không có mới dùng mặc định. Mở rộng không cần fork.

### Git của project
```
commit:    docs/  orchestra.config.yaml  .claude/commands/  traceability.yaml(bản chốt)
gitignore: .bus/  .worktrees/
```

### Test engine (bats) — công cụ tái dùng không được tự vỡ
Kiểm: adapter hiện thực đủ 4 hàm · state machine chặn transition sai · readiness check chặn /go khi hồ sơ thiếu · plan.json validate schema · escalation luật cứng kích đúng vùng nhạy cảm. CI chạy mỗi khi sửa engine.

---

## CÁC QUYẾT ĐỊNH ĐÃ CHỐT
- Claude pha 2 là **headless `claude -p`**, không TUI. Pha 1 TUI để cộng tác; pha 2 reviewer chỉ là hàm review(pack)→verdict JSON. Không trộn hai vai trong một tiến trình.
- **Mỗi task 1 git worktree** — agent làm bẩn repo riêng, verify cô lập, accept mới merge. Tránh nhiều agent giẫm chân.
- **Vòng sửa có trần** (max_reject_rounds) → quá thì BLOCKED/escalate, không lặp vô tận đốt token.
- **Gate mặc định bật** cho push/deploy/xoá/migration; code+test+build local thì tự động.
- **api-spec là OpenAPI thật** (máy-đọc), không phải markdown mô tả — để verify tích hợp + sinh stub.
- **Mức hồ sơ co giãn theo profile** (lite/standard/strict) — đừng ép hồ sơ nặng lên spike, đừng thả lỏng cho hệ lớn.

## RỦI RO LỚN NHẤT (theo thứ tự) + phòng tuyến
1. **Chất lượng test/spec pha 1** quyết định trần chất lượng pha 2. Thước đo: số vòng review trung bình/task; >2 ⇒ lỗi ở planner/testcase, không ở hạ tầng. /testcase phải sinh cả happy path LẪN edge/adversarial, và người review chúng.
2. **CLI không headless / không báo-hoàn-thành** (kilo & zcode) — KIỂM CHỨNG trước khi xây pool. Mắt xích dễ gãy nhất. Cô lập rủi ro trong adapter.
3. **Contract drift + reviewer tự tin sai** — chống bằng: cập nhật contract là bước bắt buộc của MERGE + integration build thật (bắt lỗi tích hợp) + luật escalate cứng theo vùng nhạy cảm (bất kể confidence).
4. **Rò rỉ project-specific vào engine** — mọi khác biệt project PHẢI qua config/adapter. Test "engine chạy sạch trên project chỉ có config tối thiểu". Engine cần biết bất cứ điều gì về một project cụ thể ngoài config = bug kiến trúc.

## Thước đo sức khỏe hệ thống
- Số vòng verify+review trung bình/task (>2 = spec yếu).
- % FR có đủ task+test+code xanh trước /go (phải 100%).
- Trong task máy ACCEPT mà người sau đó phát hiện sai: % lẽ ra nên escalate (cao = ngưỡng/luật lỏng).
- Review ACCEPT nhưng integration build đỏ thường xuyên = context pack thiếu / contract lỗi thời.

---

## LỘ TRÌNH BUILD (mỗi bước phải chạy được; đừng nhảy cóc)
1. **Artifact nền**: plan.json schema + templates docs/ + traceability.yaml + readiness check
2. **Runner VERIFY**: chạy done_when (test/typecheck/build) — trái tim tự-kiểm
3. **Review + context pack**: build_pack.sh + claude -p verdict (gồm ESCALATE)
4. **Daemon 1 agent** end-to-end: spawn→code→verify→review→merge
5. **Pool đa agent**: spawn động theo skill + worktree + integration build
6. **Escalation UX**: /resolve (có amend-spec) + dashboard + gates
7. **Đóng gói**: orchestra init + install.sh + versioning + adapters + test/ + CI + README zero-to-running

Khuyến nghị: làm bước 1–2 trước để lấy tín hiệu sớm liệu toàn bộ ý tưởng đáng theo, rồi mới mở rộng.

---

## VIỆC ĐẦU TIÊN CẦN LÀM VỚI CLAUDE CODE
1. Dựng skeleton repo engine theo cấu trúc trên (bin/ lib/ commands/ templates/ adapters/ profiles/ schemas/ test/ + VERSION + install.sh + README).
2. Viết plan.schema.json + orchestra.config.yaml mẫu + templates/docs/ (10 tầng, có ví dụ điền mẫu).
3. Viết adapter interface chuẩn (4 hàm) + opencode.sh + claude.sh trước; để stub kilo.sh/zcode.sh kèm TODO kiểm chứng headless.
4. Viết `orchestra init` + readiness check + runner VERIFY (bước 1–2 lộ trình).
5. Khởi tạo git, commit, đẩy lên remote.

## THÔNG TIN CẦN NGƯỜI DÙNG CUNG CẤP (hỏi nếu thiếu)
- Tên repo + cách cài (symlink PATH / clone+alias / docker).
- Project mẫu đầu tiên để `init` thử: stack (ngôn ngữ/framework), quy mô (chọn profile), lệnh build/test.
- CLI chốt cho pool đầu: xác nhận kilo/zcode/deepseek có chạy headless + cách báo "xong" chưa (nếu chưa, để stub + TODO).
- Vùng "always_human" của dự án (auth? payment? migration?) để set luật escalate cứng.

---

## GỢI Ý KHI ĐƯA VÀO CLAUDE CODE
- Mở phiên bằng: *"Đây là context thiết kế. Đọc hết, rồi dựng skeleton repo theo mục VIỆC ĐẦU TIÊN. Hỏi tôi 4 thông tin ở mục cuối trước khi điền chi tiết."*
- Yêu cầu commit **từng bước theo lộ trình**, không đổ hết một lần — dễ review và rollback.
