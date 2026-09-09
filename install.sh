#!/usr/bin/env bash
#
# install_cam_stream.sh
# Cài đặt môi trường stream camera qua domain theo hướng dẫn:
#   MediaMTX (HLS, port 8888) -> NGINX (reverse proxy, port 80) -> Cloudflared (tunnel HTTPS)
#
# Dùng cho Ubuntu/Debian (amd64 hoặc arm64).
# Chạy:  chmod +x install_cam_stream.sh && ./install_cam_stream.sh
#

set -euo pipefail

# ----- màu cho dễ đọc -----
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR ]${NC} $*"; }

# ----- không chạy bằng root trực tiếp (để sudo tự hỏi mật khẩu khi cần) -----
if [[ "${EUID}" -eq 0 ]]; then
  warn "Bạn đang chạy bằng root. Script vẫn chạy được, nhưng nên chạy bằng user thường + sudo."
fi

SUDO="sudo"
command -v sudo >/dev/null 2>&1 || SUDO=""

# ----- phát hiện kiến trúc CPU -----
ARCH_RAW="$(uname -m)"
case "${ARCH_RAW}" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) err "Kiến trúc ${ARCH_RAW} chưa hỗ trợ trong script này."; exit 1 ;;
esac
info "Kiến trúc CPU: ${ARCH_RAW} -> ${ARCH}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# =====================================================================
# 1) Gói cơ bản
# =====================================================================
info "Cập nhật apt & cài gói phụ trợ (curl, wget, tar, jq)..."
${SUDO} apt-get update -y
${SUDO} apt-get install -y curl wget tar jq ca-certificates

# =====================================================================
# 2) NGINX (kèm kiểm tra module sub_filter)
# =====================================================================
if command -v nginx >/dev/null 2>&1; then
  info "NGINX đã được cài: $(nginx -v 2>&1)"
else
  info "Cài đặt NGINX..."
  ${SUDO} apt-get install -y nginx
fi

if nginx -V 2>&1 | grep -q -- '--with-http_sub_module'; then
  info "NGINX có sẵn module sub_filter (http_sub_module). OK."
else
  warn "NGINX thiếu http_sub_module -> cài nginx-extras..."
  ${SUDO} apt-get install -y nginx-extras
fi

# =====================================================================
# 3) Cloudflared (.deb chính thức)
# =====================================================================
if command -v cloudflared >/dev/null 2>&1; then
  info "Cloudflared đã được cài: $(cloudflared --version 2>&1 | head -n1)"
else
  info "Tải & cài Cloudflared (${ARCH})..."
  CF_DEB="${TMP}/cloudflared.deb"
  wget -q -O "${CF_DEB}" \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
  ${SUDO} dpkg -i "${CF_DEB}" || ${SUDO} apt-get install -f -y
  info "Cloudflared: $(cloudflared --version 2>&1 | head -n1)"
fi

# =====================================================================
# 4) MediaMTX (binary từ GitHub release mới nhất)
# =====================================================================
if command -v mediamtx >/dev/null 2>&1; then
  info "MediaMTX đã được cài: $(mediamtx --version 2>&1 || true)"
else
  info "Lấy thông tin bản MediaMTX mới nhất..."
  MTX_URL="$(curl -fsSL https://api.github.com/repos/bluenviron/mediamtx/releases/latest \
    | jq -r ".assets[].browser_download_url" \
    | grep -E "linux_${ARCH}\.tar\.gz$" | head -n1)"

  if [[ -z "${MTX_URL}" ]]; then
    err "Không tìm được link tải MediaMTX cho linux_${ARCH}. Kiểm tra mạng/GitHub API."
    exit 1
  fi
  info "Tải MediaMTX: ${MTX_URL}"
  wget -q -O "${TMP}/mediamtx.tar.gz" "${MTX_URL}"
  tar -xzf "${TMP}/mediamtx.tar.gz" -C "${TMP}"

  ${SUDO} install -m 0755 "${TMP}/mediamtx" /usr/local/bin/mediamtx
  ${SUDO} mkdir -p /usr/local/etc
  if [[ ! -f /usr/local/etc/mediamtx.yml ]]; then
    ${SUDO} install -m 0644 "${TMP}/mediamtx.yml" /usr/local/etc/mediamtx.yml
    info "Đã đặt cấu hình mặc định: /usr/local/etc/mediamtx.yml"
  else
    warn "Đã tồn tại /usr/local/etc/mediamtx.yml -> giữ nguyên (không ghi đè)."
  fi
  info "MediaMTX: $(mediamtx --version 2>&1 || echo 'đã cài /usr/local/bin/mediamtx')"
fi

# =====================================================================
# Hoàn tất
# =====================================================================
echo
info "================ CÀI ĐẶT HOÀN TẤT ================"
echo "Đã cài:"
echo "  - NGINX        : $(command -v nginx)"
echo "  - Cloudflared  : $(command -v cloudflared)"
echo "  - MediaMTX     : $(command -v mediamtx)"
echo
echo "Bước tiếp theo (thủ công):"
echo "  1) Chạy MediaMTX:      mediamtx /usr/local/etc/mediamtx.yml"
echo "  2) Tạo config NGINX:   sudo nano /etc/nginx/sites-available/cam.conf"
echo "     (dán nội dung theo PDF, sửa IP LAN/VPN cho đúng)"
echo "     sudo ln -s /etc/nginx/sites-available/cam.conf /etc/nginx/sites-enabled/"
echo "     sudo nginx -t && sudo systemctl reload nginx"
echo "  3) Tạo tunnel:         cloudflared tunnel --url http://127.0.0.1:80"
echo "  4) Xem camera:         https://<domain-cloudflared>/CAM_F_F/"
