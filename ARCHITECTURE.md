# ARCHITECTURE.md

Tài liệu thiết kế nội bộ dành cho lập trình viên. Hãy đọc trước khi thực hiện những
thay đổi không tầm thường — một số subsystem có những "góc sắc" mà chỉ đọc code thuần
sẽ không nhận ra.

Proxy chuyển từ Windsurf sang định dạng OpenAI. Là một service Node.js không có UI,
xác thực với backend của Codeium thông qua binary Windsurf Language Server
(`language_server_linux_x64`) qua gRPC, và expose `/v1/chat/completions` cho client tương thích OpenAI.

## Cách chạy

```bash
node src/index.js          # entry point production
node --watch src/index.js  # chế độ dev (npm run dev)
```

Yêu cầu Node >= 20. Không có dependency npm nào — toàn bộ project chỉ dùng module nội tại `node:*`.
Binary Language Server phải tồn tại tại `config.lsBinaryPath` (mặc định
`/opt/windsurf/language_server_linux_x64`). Trên Windows, LS sẽ không khởi động được, nhưng
HTTP server và dashboard vẫn lên được để dev những phần không liên quan đến chat.

## Kiến trúc

```
src/
  index.js           - entry point, khởi động LS + HTTP server
  server.js          - HTTP server, dispatch route, streaming
  config.js          - env + default (.env override)
  auth.js            - pool tài khoản, theo dõi RPM, tier/blocklist, refresh credit
  models.js          - catalog model + bảng tier->models (MODEL_TIER_ACCESS)
  langserver.js      - pool LS: mỗi proxy egress duy nhất một binary
  client.js          - WindsurfClient: StartCascade / Send / poll trajectory
  windsurf.js        - protobuf builder + parser (exa.language_server_pb, exa.cortex_pb)
  proto.js           - reader/writer varint length-prefixed tối thiểu
  grpc.js            - helper gRPC qua HTTP/2 (unary call)
  connect.js         - Firebase + đăng nhập api.codeium.com (register_user)
  conversation-pool.js - pool tái sử dụng cascade_id thử nghiệm (mặc định OFF)
  runtime-config.js  - runtime-config.json: bật/tắt tính năng thử nghiệm
  cache.js           - cache phản hồi theo body trùng khớp
  handlers/
    chat.js          - /v1/chat/completions: định tuyến model, retry, tool emulation
    models.js        - /v1/models
    tool-emulation.js - tool calling bằng prompt <tool_call> (Cascade không có slot riêng)
  dashboard/
    api.js           - các route admin /dashboard/api/*
    index.html       - SPA admin một trang (dark theme kiểu shadcn)
    logger.js        - ring buffer + SSE log stream
    proxy-config.js  - cấu hình proxy toàn cục + theo tài khoản (proxy-config.json)
    model-access.js  - allow/blocklist model toàn cục (model-access.json)
    stats.js         - bộ đếm request
    windsurf-login.js - flow đăng nhập trực tiếp Windsurf (email + password)
```

**Flow request (chat):** `server.js` → `handlers/chat.js` → chọn tài khoản
(`auth.getApiKey(tried, modelKey)`) → `langserver.getLsFor(proxy)` → `WindsurfClient.cascadeChat()`
hoặc `.rawGetChatMessage()` → các unary gRPC call tới `LanguageServerService/StartCascade`,
`SendUserCascadeMessage`, polling `GetCascadeTrajectorySteps`/`GetCascadeTrajectory`.

**Cascade vs legacy:** Các model có `modelUid` đi qua flow Cascade.
Các model chỉ có `enumValue > 0` (không có `modelUid`) dùng `RawGetChatMessage` cũ.
Model mới hơn (gemini-3.0, gpt-5.2…) có cả `enumValue` LẪN `modelUid` —
chúng BẮT BUỘC dùng Cascade vì binary LS từ chối enum value cao của chúng ở endpoint legacy
với lỗi "cannot parse invalid wire-format data".

**Pool LS:** mỗi outbound proxy URL duy nhất tương ứng một LS process. Trộn các tài khoản
có proxy khác nhau vào cùng một LS sẽ gây ô nhiễm trạng thái âm thầm — `InitializeCascadePanelState`
bắt đầu fail với "The pending stream has been canceled" và mọi tài khoản đều "expired".
Luôn route tài khoản qua `getLsFor(acct.proxy)`.

**Tool emulation:** Protobuf của Cascade không có slot per-request cho schema tool do client
định nghĩa (kiểm chứng qua file `exa.cortex_pb.proto` trên đĩa — `SendUserCascadeMessageRequest`
có field 1–6 là cascade_id / items / metadata / experiment_config / cascade_config / images,
không có gì cho tool def). Khi caller truyền `tools[]` định dạng OpenAI, ta serialize chúng
vào text user dạng giao kèo `<tool_call>{...}</tool_call>` và parse các block ngược ra từ
text stream Cascade trả về. Logic nằm tại `src/handlers/tool-emulation.js`.

**Planner mode rất quan trọng.** `buildCascadeConfig()` đặt
`CascadeConversationalPlannerConfig.planner_mode = 3 (NO_TOOL)` — KHÔNG phải
`DEFAULT = 1` mà mọi repo tham khảo (pqhaz3925, AlexStrNik) đang dùng. Enum
`exa.codeium_common.ConversationalPlannerMode` có 7 giá trị:
`UNSPECIFIED=0 DEFAULT=1 READ_ONLY=2 NO_TOOL=3 EXPLORE=4 PLANNING=5 AUTO=6`.
DEFAULT giữ vòng lặp IDE-agent của Cascade luôn nóng kể cả khi `CascadeToolConfig` không được set,
khiến planner phản xạ gọi `edit_file /tmp/windsurf-workspace/...` mỗi turn, dẫn đến
(a) 20 % `stall_warm` false-positive vì step trajectory thực thi tool âm thầm khiến
`responseText` ngừng tăng trong khi status vẫn ACTIVE, (b) lỗi `"Cascade cannot create foo
because it already exists"` khi burst dùng lại tên file, (c) đường dẫn `/tmp/windsurf-workspace/`
bị leak trong response. NO_TOOL bỏ qua hoàn toàn vòng lặp này.
Stress test 04/2026 trên một host từ xa — concurrency 15 luồng opus tăng từ
13/15 → 15/15 thành công, wall time 99 s → 35 s, 0 path leak, 0 conflict tên file.

**KHÔNG** lẫn lộn `planner_mode` với `CascadeToolConfig.run_command`. Đây là hai field khác nhau —
`planner_mode` thuộc `CascadeConversationalPlannerConfig` (field 4), `run_command` thuộc
`CascadeToolConfig` (field 8 của tool config). NO_TOOL là cờ cần đặt; `tool_config` phải
giữ unset — bật `run_command` đẩy agent vào chế độ tự thực thi và làm mọi thứ tệ hơn.

## Dashboard

SPA tại `/dashboard`. Auth: bearer token = `config.API_KEY` hoặc password dashboard đã cấu hình.
8 panel: Tổng quan / Đăng nhập / Tài khoản / Model / Proxy / Log / Thống kê / Phát hiện chặn.

Trạng thái bền vững nằm ở các file JSON cạnh `src/`:
- `accounts.json` — pool tài khoản (tier, capabilities, blockedModels, credits, proxy)
- `proxy-config.json` — URL proxy toàn cục và theo tài khoản
- `model-access.json` — allow/blocklist model toàn cục
- `runtime-config.json` — toggle các tính năng thử nghiệm (cascadeConversationReuse, …)

## Quy ước

- **Ngôn ngữ:** Dashboard UI (`src/dashboard/index.html`) dùng **tiếng Việt**.
  README và các trang `docs/` GitHub Pages dùng **tiếng Việt**. Identifier và comment trong
  code giữ ở tiếng Anh.
- **Dashboard UI:** dark theme kiểu shadcn qua biến CSS (`--surface`, `--accent`, `--radius`).
  KHÔNG được dùng `alert()` / `confirm()` / `prompt()` của trình duyệt. Hãy dùng
  `App.confirm(title, desc, opts)` và `App.prompt(title, desc, fields)` — chúng render modal
  có style. `App.confirm` hỗ trợ `opts.html`, `opts.wide`, `opts.titleHtml`, `opts.danger`, `opts.okText`.
- **Không thêm dependency npm.** Bám vào module nội tại `node:*`. Nếu cần protobuf, hãy tự viết
  trong `proto.js`.
- **Lỗi không được tăng error counter của tài khoản:** rate limit, `permission_denied`,
  `failed_precondition`, và "internal error occurred (error ID: …)" từ upstream.
  Xem `reportInternalError` / `markRateLimited` trong `auth.js`.
- **Log:** dùng `log.info/warn/error/debug` từ `config.js` — chúng đẩy lên panel log của
  dashboard qua `dashboard/logger.js`.
- **Line ending git:** repo có `text=auto`; checkout trên Windows có thể cảnh báo LF→CRLF khi save. Bỏ qua.

## Triển khai

Có hai cách được hỗ trợ; cả hai đều tránh được "zombie process trap" của `pm2 restart`:

**PM2 (phổ biến):**

```bash
pm2 stop windsurf-api && pm2 delete windsurf-api
fuser -k 3003/tcp 2>/dev/null
sleep 2
pm2 start src/index.js --name windsurf-api --cwd /path/to/WindsurfPoolAPI
```

**Docker:** `docker compose up -d --build` — xem `Dockerfile` và `docker-compose.yml`.
Bạn vẫn cần mount binary Windsurf Language Server vào container
(`/opt/windsurf/language_server_linux_x64`); không thể đóng gói cùng image vì lý do giấy phép.

KHÔNG dùng `pm2 restart windsurf-api` — trên một số tổ hợp Node/PM2, lệnh này để lại
process cũ giữ port 3003, process mới sẽ âm thầm fallback sang port khác mà không cảnh báo.

## Các "gotcha" đã biết

1. **Tier Free** chỉ phục vụ `gpt-4o-mini` và `gemini-2.5-flash` — mọi model Claude và premium
   sẽ trả `permission_denied`. Hardcode trong `MODEL_TIER_ACCESS.free`. Có thể bypass bằng
   `BYPASS_ENTITLEMENT=1` để test xem upstream Windsurf có chặn hay không.
2. **Workspace bị xoá khi khởi động** — `src/index.js` chạy `rm -rf /tmp/windsurf-workspace/*`
   trước khi LS khởi động. Bỏ bước này thì các file do tool chỉnh sửa file của Cascade tạo ra
   sẽ tồn tại qua các lần restart và model sẽ bắt đầu kể chuyện "đang sửa" những file mà
   caller không hề nhắc đến.
3. **`responseText` vs `modifiedText`:** trong lúc streaming, hãy ưu tiên `responseText`
   (chỉ append). Chỉ topup từ `modifiedText` khi idle nếu nó là phần mở rộng strict prefix
   của `responseText`. Xem block comment lớn trong `client.js` ở vòng poll cascade.
4. **Firebase API key** dùng cho auth Windsurf là `AIzaSyDsOl-1XpT5err0Tcnx8FFod1H8gVGIycY`
   (lấy từ `https://windsurf.com/_next/static/chunks/46097-*.js`). Đã thử ba key khác và
   xác nhận KHÔNG hoạt động — đừng rotate sang chúng.
5. **Số field protobuf** được tự viết trong `src/windsurf.js` và `src/proto.js`.
   Khi Windsurf ship model hoặc capability mới, hãy diff với descriptor proto
   `exa.cortex_pb` / `exa.language_server_pb` của binary LS trước khi thêm field —
   wire format varint không tha thứ cho schema drift âm thầm.
