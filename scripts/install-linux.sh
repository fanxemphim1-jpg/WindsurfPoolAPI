#!/usr/bin/env bash
# ─────────────────────────────────────────────────────
# WindsurfPoolAPI — Trình cài đặt Linux (x64 / arm64)
# Cài đặt như một dịch vụ systemd dưới user đang chạy script.
# Tự động tải binary `language_server_linux_x64` từ mirror
# chính thức của Windsurf nếu chưa có.
# ─────────────────────────────────────────────────────
set -e

INSTALL_DIR="$HOME/.windsurfapi"
SERVICE_NAME="windsurfpoolapi"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LS_DIR="/opt/windsurf"
WINDSURF_UPDATE_API="https://windsurf-stable.codeium.com/api/update/linux-x64/stable/latest"

echo "╔══════════════════════════════════════════╗"
echo "║  Trình cài đặt WindsurfPoolAPI (Linux)   ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Kiểm tra Node.js ───────────────────────────
if ! command -v node &>/dev/null; then
  echo "❌ Không tìm thấy Node.js. Vui lòng cài đặt Node.js >= 20:"
  echo "   Ubuntu/Debian:  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt install -y nodejs"
  echo "   Fedora/RHEL:    sudo dnf install -y nodejs"
  echo "   Arch:           sudo pacman -S nodejs"
  exit 1
fi

NODE_VER=$(node -e "console.log(process.versions.node.split('.')[0])")
if [ "$NODE_VER" -lt 20 ]; then
  echo "❌ Cần Node.js >= 20 (hiện tại $(node --version))"
  exit 1
fi
echo "✅ Node.js $(node --version)"

# ── Phát hiện kiến trúc ────────────────────────
# Windsurf official chỉ phát hành binary cho linux-x64. Trên ARM64 ta sẽ
# tải binary x64 và chạy qua qemu-user-static (binfmt). Hiệu năng giảm
# 3-5 lần nhưng vẫn dùng được cho dev/test.
ARCH=$(uname -m)
LS_BIN_NAME="language_server_linux_x64"
NEED_QEMU=0
case "$ARCH" in
  x86_64|amd64)
    echo "✅ Kiến trúc: $ARCH (chạy native)"
    ;;
  aarch64|arm64)
    echo "⚠️  Kiến trúc: $ARCH — Windsurf không có build ARM64 chính thức."
    echo "   Sẽ chạy binary x86_64 thông qua qemu-user-static (chậm hơn native ~3-5×)."
    NEED_QEMU=1
    ;;
  *)
    echo "⚠️  Kiến trúc lạ: $ARCH — sẽ thử dùng binary x86_64 (có thể không tương thích)."
    NEED_QEMU=1
    ;;
esac

LS_PATH="${LS_DIR}/${LS_BIN_NAME}"

# ── Kiểm tra công cụ cần thiết ─────────────────
for tool in curl tar; do
  if ! command -v "$tool" &>/dev/null; then
    echo "❌ Thiếu công cụ '$tool'. Hãy cài đặt rồi chạy lại."
    exit 1
  fi
done

# ── Cài đặt qemu-user-static (chỉ trên ARM64) ──
setup_qemu() {
  if [ "$NEED_QEMU" -ne 1 ]; then return 0; fi
  if [ -x /usr/bin/qemu-x86_64-static ] || [ -x /usr/bin/qemu-x86_64 ]; then
    echo "✅ qemu-user-static đã có sẵn"
  else
    echo "⬇️  Đang cài qemu-user-static (cần sudo)..."
    if command -v apt-get &>/dev/null; then
      sudo apt-get update -qq && sudo apt-get install -y qemu-user-static binfmt-support
    elif command -v dnf &>/dev/null; then
      sudo dnf install -y qemu-user-static
    elif command -v pacman &>/dev/null; then
      sudo pacman -S --noconfirm qemu-user-static qemu-user-static-binfmt
    else
      echo "❌ Không nhận diện được package manager. Hãy tự cài qemu-user-static rồi chạy lại."
      return 1
    fi
  fi

  # Đăng ký binfmt nếu chưa active
  if [ ! -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ] && [ ! -e /proc/sys/fs/binfmt_misc/qemu-i386 ]; then
    echo "⬇️  Đang đăng ký binfmt cho x86_64..."
    if command -v update-binfmts &>/dev/null; then
      sudo update-binfmts --enable qemu-x86_64 || true
    fi
    if [ ! -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ]; then
      sudo systemctl restart systemd-binfmt 2>/dev/null || true
    fi
  fi

  if [ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ]; then
    echo "✅ binfmt qemu-x86_64 đã active — có thể chạy binary x86_64 trên $ARCH"
  else
    echo "⚠️  Không kích hoạt được binfmt qemu-x86_64 tự động."
    echo "   Bạn có thể chạy bằng tay: sudo /usr/bin/qemu-x86_64-static $LS_PATH"
  fi

  # qemu-user chế độ P cần dynamic linker x86_64 ở /lib64/ld-linux-x86-64.so.2
  # và shared libs cơ bản. Trên host ARM64 thuần, các file này không có sẵn —
  # phải bật multiarch amd64 và cài libc/libstdc++/libgcc cho amd64.
  if ! [ -e /lib64/ld-linux-x86-64.so.2 ]; then
    if command -v dpkg &>/dev/null && command -v apt-get &>/dev/null; then
      echo "⬇️  Cài x86_64 glibc multiarch (cần thiết cho qemu-user mode P)..."
      sudo dpkg --add-architecture amd64

      # Trên ARM Ubuntu, mặc định apt sources trỏ về ports.ubuntu.com — repo
      # này CHỈ host arm64/ppc/s390 và sẽ trả 404 cho amd64. Phải thêm source
      # archive.ubuntu.com riêng cho amd64 và giới hạn source ports cho arm64.
      if grep -q "ports.ubuntu.com" /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null; then
        echo "   Phát hiện ports.ubuntu.com — đang thêm source archive.ubuntu.com cho amd64..."
        # deb822 format (Ubuntu 24.04+): thêm Architectures: arm64 nếu chưa có
        for f in /etc/apt/sources.list.d/*.sources; do
          [ -f "$f" ] || continue
          if ! grep -q "^Architectures:" "$f"; then
            sudo sed -i '/^Suites:/a Architectures: arm64' "$f" || true
          fi
        done
        # Legacy format
        if [ -f /etc/apt/sources.list ]; then
          sudo sed -i -E 's|^deb (http)|deb [arch=arm64] \1|' /etc/apt/sources.list || true
        fi
        # Suy ra codename từ /etc/os-release
        CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-noble}")
        sudo tee /etc/apt/sources.list.d/amd64.list > /dev/null <<EOF
deb [arch=amd64] http://archive.ubuntu.com/ubuntu ${CODENAME} main restricted universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu ${CODENAME}-updates main restricted universe multiverse
deb [arch=amd64] http://security.ubuntu.com/ubuntu ${CODENAME}-security main restricted universe multiverse
EOF
      fi

      sudo apt-get update -qq
      sudo apt-get install -y libc6:amd64 libstdc++6:amd64 libgcc-s1:amd64 \
        || echo "⚠️  Cài libc/libstdc++/libgcc cho amd64 thất bại — bạn có thể cần kiểm tra repo apt."
    else
      echo "⚠️  Distro không phải Debian/Ubuntu — bạn cần tự cài x86_64 glibc multiarch để qemu-user mode P chạy được."
    fi
  fi

  if [ -e /lib64/ld-linux-x86-64.so.2 ]; then
    echo "✅ Dynamic linker x86_64 đã có tại /lib64/ld-linux-x86-64.so.2"
  else
    echo "⚠️  Vẫn thiếu /lib64/ld-linux-x86-64.so.2 — Language Server sẽ không khởi động được."
    echo "   Tham khảo: sudo dpkg --add-architecture amd64 && sudo apt-get install libc6:amd64"
  fi
}
setup_qemu || true

# ── Tự động tải Windsurf Language Server ───────
download_language_server() {
  echo ""
  echo "⬇️  Tự động tải Windsurf Linux từ mirror chính thức..."
  echo "    (binary này không thể đóng gói cùng repo do giấy phép của Windsurf)"

  # Lấy URL tarball mới nhất từ API update
  local update_json
  if ! update_json=$(curl -fsSL "$WINDSURF_UPDATE_API"); then
    echo "❌ Không gọi được API update của Windsurf: $WINDSURF_UPDATE_API"
    return 1
  fi

  local tarball_url
  tarball_url=$(echo "$update_json" | grep -o '"url":"[^"]*' | head -1 | cut -d'"' -f4)
  if [ -z "$tarball_url" ]; then
    echo "❌ Không trích xuất được URL tarball từ phản hồi: $update_json"
    return 1
  fi

  local windsurf_version
  windsurf_version=$(echo "$update_json" | grep -o '"windsurfVersion":"[^"]*' | head -1 | cut -d'"' -f4)
  echo "    Phiên bản Windsurf: ${windsurf_version:-unknown}"
  echo "    URL: $tarball_url"

  local tmpdir
  tmpdir=$(mktemp -d /tmp/windsurf-install.XXXXXX)
  trap "rm -rf '$tmpdir'" RETURN

  echo "    Đang tải về (~270 MB)..."
  if ! curl -fL --progress-bar -o "$tmpdir/windsurf.tar.gz" "$tarball_url"; then
    echo "❌ Tải tarball thất bại"
    return 1
  fi

  echo "    Đang trích xuất ${LS_BIN_NAME}..."
  if ! tar -xzf "$tmpdir/windsurf.tar.gz" \
        -C "$tmpdir" \
        "Windsurf/resources/app/extensions/windsurf/bin/${LS_BIN_NAME}" 2>/dev/null; then
    echo "    Đường dẫn chuẩn không có, thử tìm trong tarball..."
    local extracted
    extracted=$(tar -tzf "$tmpdir/windsurf.tar.gz" | grep -E "/${LS_BIN_NAME}\$" | head -1)
    if [ -z "$extracted" ]; then
      echo "❌ Không tìm thấy ${LS_BIN_NAME} trong tarball"
      return 1
    fi
    tar -xzf "$tmpdir/windsurf.tar.gz" -C "$tmpdir" "$extracted"
  fi

  local extracted_path
  extracted_path=$(find "$tmpdir" -name "${LS_BIN_NAME}" -type f | head -1)
  if [ -z "$extracted_path" ]; then
    echo "❌ Trích xuất xong nhưng không thấy file ${LS_BIN_NAME}"
    return 1
  fi

  echo "    Cài đặt vào ${LS_PATH}..."
  sudo mkdir -p "$LS_DIR"
  sudo cp "$extracted_path" "$LS_PATH"
  sudo chmod +x "$LS_PATH"
  echo "✅ Đã cài đặt Language Server tại $LS_PATH"
}

if [ ! -x "$LS_PATH" ]; then
  if ! download_language_server; then
    echo ""
    echo "⚠️  Không tải được binary tự động."
    echo "   Cài đặt thủ công:"
    echo "   1. Tải Windsurf Linux tarball từ https://windsurf.com/editor/download"
    echo "   2. Trích xuất ${LS_BIN_NAME} vào $LS_DIR/"
    echo "   3. chmod +x $LS_PATH"
    echo ""
    read -p "   Tiếp tục cài đặt mà không có Language Server? [y/N] " yn
    [[ "$yn" != "y" && "$yn" != "Y" ]] && exit 1
  fi
else
  echo "✅ Đã có Language Server tại $LS_PATH (bỏ qua bước tải)"
fi

# ── Cài đặt file của project ───────────────────
echo "📁 Cài đặt vào $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -R "$SCRIPT_DIR/../src" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/../package.json" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/../README.md" "$INSTALL_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/../CHANGELOG.md" "$INSTALL_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/../LICENSE"      "$INSTALL_DIR/" 2>/dev/null || true

# ── Tạo unit systemd ───────────────────────────
if [ -d /etc/systemd/system ]; then
  echo "🛠  Ghi unit systemd vào $SERVICE_FILE ..."
  sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=WindsurfPoolAPI — proxy nhiều tài khoản cho Windsurf
After=network.target

[Service]
Type=simple
User=$USER
Group=$(id -gn)
WorkingDirectory=$INSTALL_DIR
ExecStart=$(command -v node) $INSTALL_DIR/src/index.js
Restart=on-failure
RestartSec=5
Environment=PORT=3003
Environment=LOG_LEVEL=info
Environment=LS_BINARY_PATH=$LS_PATH
$([ "$NEED_QEMU" = "1" ] && printf "Environment=LS_READY_TIMEOUT_MS=120000\n")
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now "$SERVICE_NAME"

  echo ""
  echo "✅ Đã cài đặt xong! Dịch vụ đang chạy."
  echo ""
  echo "Lệnh hữu ích:"
  echo "  sudo systemctl status $SERVICE_NAME"
  echo "  sudo systemctl restart $SERVICE_NAME"
  echo "  sudo journalctl -u $SERVICE_NAME -f"
  echo ""
  echo "Dashboard: http://localhost:3003/dashboard"
else
  echo "⚠️  Không có /etc/systemd/system — bỏ qua cài đặt service."
  echo "   Khởi động thủ công:"
  echo "   cd $INSTALL_DIR && node src/index.js"
fi
