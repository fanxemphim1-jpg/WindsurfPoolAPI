# Hướng dẫn đóng góp

Cảm ơn bạn quan tâm đến việc đóng góp cho **WindsurfPoolAPI**. Tài liệu này mô tả cách chuẩn bị môi trường, quy ước code và quy trình PR.

## Chuẩn bị môi trường

- **Node.js ≥ 20**
- **Binary Windsurf Language Server** (`language_server_linux_x64`), mặc định đặt tại `/opt/windsurf/`
- Không cần `npm install` — dự án **không có dependency npm nào**, chỉ dùng module nội tại `node:*`

```bash
git clone https://github.com/<your-fork>/WindsurfPoolAPI.git
cd WindsurfPoolAPI

# Khởi động nhanh (foreground)
node src/index.js

# Chế độ phát triển (tự khởi động lại khi file thay đổi)
node --watch src/index.js
```

Service mặc định lắng nghe trên `http://0.0.0.0:3003`, dashboard tại `/dashboard`.

## Quy ước code

### Nguyên tắc không có dependency npm

- **Không** thêm bất kỳ `npm install <xxx>` nào. Cần HTTP / protobuf / crypto? Dùng `node:https` / tự viết varint / `node:crypto`.
- Đây là quyết định thiết kế: bề mặt bảo mật nhỏ hơn, khởi động nhanh hơn, triển khai đơn giản hơn.
- Trường `dependencies` trong `package.json` phải luôn rỗng (CI sẽ kiểm tra).

### Phong cách code

- Dùng ES modules (`import`/`export`), không dùng CommonJS.
- Comment viết bằng **tiếng Anh**, UI Dashboard viết bằng **tiếng Việt**.
- Đặt tên biến theo `camelCase`, class theo `PascalCase`.
- Mọi lỗi/log đều đi qua `log.info/warn/error/debug` (từ `src/config.js`).

### Tổ chức file

Tham khảo `ARCHITECTURE.md` để biết cách phân chia module. Khi thêm tính năng mới:

- HTTP entry point → `src/server.js`
- Logic xử lý request → `src/handlers/*.js`
- API backend của Dashboard → `src/dashboard/api.js`
- Frontend Dashboard → `src/dashboard/index.html`
- Trạng thái bền vững → ghi vào file `*.json` riêng (đã thêm vào `.gitignore`)

## Quy ước commit

Áp dụng định dạng [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat: tính năng mới
fix:  sửa bug
docs: tài liệu
refactor: refactor (không ảnh hưởng tính năng)
perf: tối ưu hiệu năng
test: test
chore: build / scaffold
```

Ví dụ:

```text
feat(dashboard): add token usage export/import endpoints
fix(cascade): handle panel-state-not-found on Send retry
```

## Checklist khi mở PR

Trước khi mở PR hãy kiểm tra:

- [ ] `find src -name '*.js' -exec node --check {} \;` chạy pass hết
- [ ] Không thêm dependency npm
- [ ] Không hardcode đường dẫn, IP, credential
- [ ] Tính năng mới có mô tả trong README và/hoặc ARCHITECTURE.md
- [ ] File nhạy cảm (`accounts.json` / `stats.json` / `.env` / `logs/` / `data/`) **không** được commit

## Test

Hiện tại dự án chưa có bộ unit test chính thức, nhưng có thể xác minh các đường dẫn quan trọng như sau:

### Smoke test cục bộ

```bash
# Khởi động service
node src/index.js &

# Kiểm tra availability cơ bản
curl -fsS http://localhost:3003/health
curl -fsS http://localhost:3003/v1/models | head -20

# Đăng nhập Dashboard
curl -H "X-Dashboard-Password: $DASHBOARD_PASSWORD" \
  http://localhost:3003/dashboard/api/stats
```

### Chat end-to-end (cần đã thêm tài khoản)

```bash
curl -sS http://localhost:3003/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"say hi"}],"stream":false}'
```

## Phản hồi

- **Bug**: [GitHub Issues](https://github.com/<org>/WindsurfPoolAPI/issues), kèm vài dòng cuối của `logs/error-*.jsonl`.
- **Đề xuất tính năng**: tạo Issue và mô tả use case.
- **Lỗ hổng bảo mật**: vui lòng **liên hệ riêng** qua email với maintainer, không công khai trên Issues.

## Giấy phép

Khi đóng góp code, bạn đồng thuận phát hành theo giấy phép MIT.
