# Nhật ký thay đổi

## v2.0.4 (2026-04-23)

### Bảo mật & Ổn định

- **Trung hoà danh tính** — Viết lại "You are X" → "The assistant is X" trong system prompt của Cascade để tránh cơ chế phát hiện prompt-injection của Claude 4.7 (#41).
- **Phòng thủ prototype pollution** — `deepMerge` trong runtime-config bỏ qua các key `__proto__` / `constructor` / `prototype`.
- **Tăng cường sanitize đường dẫn** — Tự phát hiện repo-root động kèm length guard; redact đường dẫn workspace sandbox; `sanitizeToolCall` cũng quét object `input` (#38).

### Tính năng mới

- **Gợi ý ngôn ngữ phản hồi** (`handlers/chat.js`) — Tự phát hiện CJK/JP/KR trong tin nhắn người dùng và chèn nhắc nhở để model trả lời đúng ngôn ngữ. Thứ tự nhận diện: JP (kana) → KR (hangul) → CJK để tránh nhầm tiếng Nhật thành tiếng Trung.
- **Quản lý prompt danh tính** (`runtime-config.js`, `dashboard/api.js`) — Template prompt danh tính theo từng provider, có CRUD trong dashboard qua `GET/PUT/DELETE /dashboard/api/identity-prompts`. Hỗ trợ 10 provider (Anthropic, OpenAI, Google, DeepSeek, xAI, Alibaba, Moonshot, Zhipu, MiniMax, Windsurf).
- **Ngân sách history Cascade** (`client.js`) — Byte budget hiện đã tính cả độ dài system prompt; model context 1M có budget 900KB (env `CASCADE_1M_HISTORY_BYTES`). History render bằng tag XML `<human>`/`<assistant>`.
- **Scaffold workspace** (`client.js`) — Mỗi tài khoản có thư mục workspace riêng, có sẵn `package.json`, `.gitignore` và `git init` để Cascade thấy context giống thật.

### Hiệu năng

- **Pool session HTTP/2** (`grpc.js`) — Tái sử dụng connection HTTP/2 theo từng port LS thay vì theo từng call. Có handler GOAWAY để evict chủ động. Thêm header `user-agent: grpc-node/1.108.2` cho unary call.
- **Nâng cấp conversation pool** (`conversation-pool.js`) — `stripMetaTags` xoá các meta tag động của Claude Code trước khi fingerprint; turn ổn định (chỉ user + tool) cho fingerprint; TTL 30 phút (env `CASCADE_POOL_TTL_MS`); interval prune nền. Bật mặc định.

### Sửa lỗi

- **Timing warm stall** (`client.js`) — Chuyển ra sau khi fetch status để dùng status hiện tại của poll, tránh false warm-stall khi cascade vừa chuyển IDLE.
- **Ngưỡng cold stall** (`client.js`) — Dùng độ dài prompt cuối cùng đã ráp thay vì độ dài raw message.
- **Idle break guard** (`client.js`) — Điều kiện `growthSettled` ngăn kết thúc sớm trong giai đoạn thinking.
- **Double-settle guard** (`grpc.js`, `client.js`) — Cờ `done` trong callback Raw và gRPC ngăn promise resolve hai lần.
- **Dọn session** (`langserver.js`) — `closeSessionForPort` được gọi khi LS restart/stop để tránh leak pool session HTTP/2.
- **`sessionId` theo từng LS** (`client.js`, `windsurf.js`) — Đường legacy Raw tái sử dụng session ID ổn định theo từng LS, khớp với hành vi của Windsurf IDE thật.

---

## v2.0.3 (2026-04-22)

### Tính năng mới

- **Hỗ trợ upload ảnh** (`src/image.js`, `client.js`, `windsurf.js`)
  Đã hỗ trợ request multimodal với content block `image_url`. Ảnh được trích xuất từ mảng content định dạng OpenAI và Anthropic, được validate (chống SSRF, giới hạn 5MB, giới hạn độ sâu redirect), và truyền dưới dạng proto field 6 cho Cascade. Pipeline vision tự động bật qua planner mode DEFAULT khi có ảnh.

- **80+ alias tên model** (`models.js`)
  - Tên có ngày của Anthropic (`claude-3-5-sonnet-20241022`, `claude-sonnet-4-20250514`, …)
  - Tên có ngày của OpenAI (`gpt-4o-2024-11-20`, `gpt-4.1-2025-04-14`, …)
  - Alias không chứa từ "claude" cho Cursor (`ws-opus`, `sonnet-4.6`, `opus-4.7-max`, …)
  - Client như Claude Code, Cursor và Anthropic SDK có thể nói chuyện với API này mà không cần dịch tên thủ công.

- **Model mới**: `gpt-5.4-none`, `gpt-5.4-high`
- **`getModelKeysByEnum()`** — hàm tra ngược enum model → key catalog.

### Sửa lỗi

- **`maxAttempts` động** (`handlers/chat.js`)
  Số lần retry hiện scale theo kích thước pool tài khoản đang active (tối thiểu 3, tối đa 10) thay vì hardcode 3. Sửa lỗi pool lớn nhưng 3 tài khoản đầu đã bị rate-limit khiến tài khoản khoẻ không bao giờ được chạm tới.

- **`enumValue` của `kimi-k2`** sửa từ 0 → 323 (bật fallback RawGetChatMessage legacy)
- **Bỏ `qwen-3-coder` bị hỏng** — cascade server không đăng ký route nào cho model này; request luôn fail với 'model not found'.
- **`MODEL_TIER_ACCESS.pro`** đổi sang dynamic getter để model merge từ catalog cloud tự động được tính vào entitlement của tier Pro.

### Cải tiến server

- **`/favicon.ico` → 204** — bỏ noise console của trình duyệt khi vào dashboard.
- **Validate message rỗng** — cả `/v1/chat/completions` và `/v1/messages` giờ trả 400 đúng nghĩa khi mảng messages rỗng, thay vì truyền xuống handler.

---

## v2.0.2 (2026-04-21)

### Sửa lỗi — CC / SSE Streaming

Sửa hiện tượng "Claude Code có vẻ bị treo / một phần nội dung không hiển thị" được báo trên các model nặng thinking.

- **`message_start` + `ping` ngay khi vào stream** (`handlers/messages.js`)
  SSE Anthropic giờ phát envelope message ban đầu cùng một ping *trước khi* chờ token đầu tiên từ upstream. UI của CC thoát trạng thái "connecting" trong vài mili-giây thay vì im lặng suốt cả khoảng thời gian LS cold-start + first-token của Windsurf (trước đây 8–15s với model Opus thinking).
- **Thêm field `signature` cho thinking content block** (`handlers/messages.js`)
  `content_block_start` cho block thinking giờ kèm `signature: ''`. Một số bản CC âm thầm bỏ block thinking nếu thiếu field này.
- **Heartbeat 15s → 5s** (`handlers/chat.js`)
  Giữ idle-watchdog của CC vui vẻ qua các pause reasoning dài. Chi phí mạng không đáng kể (comment SSE, ~6 byte).
- **`:ping` ngay đầu cho `/v1/chat/completions`** (`handlers/chat.js`)
  Client giao thức OpenAI cũng được lợi từ byte-flow lập tức thay vì warmup im lặng.
- **TCP NoDelay + flushHeaders + keepalive** (`server.js`)
  Tắt Nagle ở endpoint streaming nên các delta nhỏ liên tục không bị gộp thành batch 40ms. `flushHeaders()` đẩy header response cho client ngay sau `writeHead`.

### Xác minh

Đo time-to-first-byte trên `/v1/messages`: **4ms** (trước đây vài giây trên LS lạnh).

---

## v2.0.1 (2026-04-21)

### Tính năng tích hợp từ upstream dwgx/WindsurfAPI

- Ngưỡng cold-stall động (30s–90s tuỳ độ dài input)
- Endpoint OAuth login (`POST /oauth-login`) cho Google/GitHub Firebase auth
- Token persistence qua `setAccountTokens` — refresh + id token sống sót sau restart
- Refresh thủ công Firebase tự ghi credential mới xuống đĩa

### Đổi thương hiệu

- Đổi tên dự án thành **WindsurfPoolAPI**
- README song ngữ chuyên nghiệp (EN/CN) với screenshot dashboard
- Đổi tên repo GitHub + cập nhật topic

---

## v2.0.0 (2026-04-20)

### Tính năng mới

- **Thao tác hàng loạt** — Chọn nhiều tài khoản và bật/tắt chúng cùng một lúc qua dashboard. Mọi thay đổi được persist xuống `accounts.json` ngay lập tức.
- **Hiển thị quota theo tài khoản** — Dashboard giờ hiển thị thanh quota daily/weekly/prompt riêng cho từng tài khoản, có màu theo phần trăm và tooltip thời gian reset.
- **Nhãn tài khoản trong thống kê** — Bảng chi tiết request hiện hiển thị email tài khoản thay vì prefix API key khó hiểu.
- **Trạng thái lỗi bền vững** — Thay đổi trạng thái lỗi/hồi phục của tài khoản (`reportError`/`reportSuccess`) hiện được ghi xuống đĩa, sống sót qua restart.
- **macOS LaunchAgent** — Plist mẫu để tự khởi động khi boot, có khôi phục sau crash.

### Cải tiến

- **Catalog model** — Thêm họ Claude Opus 4.7 phân tier theo effort, GPT-5.4, Gemini 3.1 Pro, GLM-5.1, Kimi K2.5, MiniMax M2.5 và nhiều model khác (tổng 87+).
- **Hỗ trợ tier Trial** — Tài khoản trial giờ được nhận diện đúng là pro-tier, được dùng mọi model.
- **API batch status** — Endpoint mới `POST /accounts/batch-status` nhận `{ids[], status}` cho thao tác hàng loạt.
- **Dashboard UX** — Thêm cột checkbox với select-all/invert/clear, batch action bar có dialog xác nhận.

### Sửa lỗi

- Sửa `reportError` và `reportSuccess` không persist thay đổi status xuống đĩa.
- Sửa stats detail hiển thị prefix API key thô thay vì tên tài khoản đọc được.

---

## v1.2.0 (2026-04-19)

- Bản phát hành công khai đầu tiên.
- Pool nhiều tài khoản, cân bằng tải theo RPM.
- Proxy hai giao thức OpenAI + Anthropic.
- SPA dashboard với quản lý tài khoản, log realtime, biểu đồ sử dụng.
- Tool call emulation cho flow Cascade.
- Streaming SSE có heartbeat và usage chunk.
- Không có dependency npm.
