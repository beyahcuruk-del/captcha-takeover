#!/usr/bin/env bash
# install.sh — Install all dependencies for Hermes captcha takeover stack on Ubuntu.
#
# Stack: Xvfb + fluxbox + Chrome (CDP) + x11vnc + noVNC (websockify) + Tailscale.
#
# Run as a user with sudo. Re-running is safe; apt and tailscale handle idempotency.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { printf "${GREEN}[install]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[warn]${NC} %s\n" "$*"; }
die()  { printf "${RED}[error]${NC} %s\n" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "Jangan run sebagai root. Run sebagai user biasa, sudo akan dipanggil saat perlu."

if ! command -v sudo >/dev/null 2>&1; then
  die "sudo tidak tersedia. Install dulu: apt install sudo"
fi

. /etc/os-release 2>/dev/null || die "/etc/os-release tidak ada — bukan Linux dengan os-release."
[[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" =~ debian ]] || warn "Bukan Ubuntu/Debian — script ini ditulis untuk Ubuntu, mungkin perlu adjust."

log "Update apt index..."
sudo apt-get update -y

log "Install Xvfb, fluxbox, x11vnc, websockify, novnc, dan dependencies dasar..."
sudo apt-get install -y --no-install-recommends \
  xvfb \
  fluxbox \
  x11vnc \
  websockify \
  novnc \
  curl \
  wget \
  ca-certificates \
  gnupg \
  apt-transport-https \
  jq \
  procps \
  net-tools \
  xdotool \
  imagemagick \
  x11-utils \
  python3 \
  python3-pip \
  python3-websockets \
  python3-requests

# Verify Python deps are importable from the python3 in PATH (kalau ada pyenv/conda
# yang nge-shim, apt-installed deps gak ke-detect). Install via pip kalau perlu.
if ! python3 -c "import requests, websockets" >/dev/null 2>&1; then
  warn "python3 di PATH gak punya 'requests' atau 'websockets' — install via pip"
  python3 -m pip install --user --break-system-packages websockets requests 2>/dev/null \
    || python3 -m pip install --user websockets requests \
    || die "Gagal install python deps. Install manual: pip install websockets requests"
fi

# ---------- Google Chrome ----------
# Cek via dpkg (lebih reliable daripada `command -v` — di beberapa env ada wrapper script
# yang nge-shim nama "google-chrome" tapi bukan binary asli).
if dpkg -s google-chrome-stable >/dev/null 2>&1; then
  log "Google Chrome stable sudah terinstall: $(/usr/bin/google-chrome-stable --version 2>/dev/null || echo unknown)"
else
  log "Install Google Chrome stable..."
  TMP_DEB="$(mktemp --suffix=.deb)"
  wget -q -O "$TMP_DEB" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
  sudo apt-get install -y "$TMP_DEB" || sudo apt-get install -fy
  rm -f "$TMP_DEB"
  log "Chrome terinstall: $(/usr/bin/google-chrome-stable --version)"
fi

# ---------- Tailscale ----------
if command -v tailscale >/dev/null 2>&1; then
  log "Tailscale sudah terinstall: $(tailscale version | head -1)"
else
  log "Install Tailscale (official script)..."
  curl -fsSL https://tailscale.com/install.sh | sh
fi

# Catatan: tailscale up dilakukan di step terpisah (interaktif) — jangan auto-up di sini.

# ---------- cloudflared (untuk TUNNEL_MODE=cloudflared) ----------
# Optional: kalau lu mau pake cloudflared quick tunnel sebagai alternative ke Tailscale.
# Skip kalau lu udah pake Tailscale dan gak butuh ini.
if command -v cloudflared >/dev/null 2>&1; then
  log "cloudflared sudah terinstall: $(cloudflared --version 2>&1 | head -1)"
else
  log "Install cloudflared (quick tunnel — alternative Tailscale, no account needed)..."
  TMP_BIN="$(mktemp)"
  if wget -q -O "$TMP_BIN" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"; then
    chmod +x "$TMP_BIN"
    sudo mv "$TMP_BIN" /usr/local/bin/cloudflared
    log "cloudflared terinstall: $(cloudflared --version 2>&1 | head -1)"
  else
    rm -f "$TMP_BIN"
    log "WARN: cloudflared download gagal — skip. Lu masih bisa pake Tailscale."
  fi
fi

# ---------- Direktori kerja ----------
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$HOME/.hermes-takeover"
mkdir -p "$RUN_DIR/logs" "$RUN_DIR/run" "$RUN_DIR/chrome-profile"
chmod 700 "$RUN_DIR"

# Generate VNC password kalau belum ada
VNC_PASSWD_FILE="$RUN_DIR/vncpasswd"
if [[ ! -f "$VNC_PASSWD_FILE" ]]; then
  RANDOM_PASS="$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)"
  x11vnc -storepasswd "$RANDOM_PASS" "$VNC_PASSWD_FILE" >/dev/null
  chmod 600 "$VNC_PASSWD_FILE"
  echo "$RANDOM_PASS" > "$RUN_DIR/vncpasswd.txt"
  chmod 600 "$RUN_DIR/vncpasswd.txt"
  log "VNC password baru dibuat. Lihat di: $RUN_DIR/vncpasswd.txt"
else
  log "VNC password sudah ada di $VNC_PASSWD_FILE (skip)"
fi

# ---------- env file ----------
ENV_FILE="$INSTALL_DIR/scripts/env.sh"
if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<'EOF'
# env.sh — konfigurasi runtime untuk Hermes captcha takeover.
# Edit sesuai kebutuhan, lalu source sebelum jalanin script lain.

# Display virtual yang dipake (jangan tabrakan sama display fisik :0)
export DISPLAY_NUM=":1"
export SCREEN_GEOMETRY="1280x800x24"

# Port-port (bind ke 127.0.0.1 / Tailscale aja, jangan public)
export VNC_PORT="5901"
export NOVNC_PORT="6080"
export CHROME_CDP_PORT="9222"

# Path
export RUN_DIR="$HOME/.hermes-takeover"
export CHROME_USER_DATA_DIR="$RUN_DIR/chrome-profile"
export VNC_PASSWD_FILE="$RUN_DIR/vncpasswd"
export LOG_DIR="$RUN_DIR/logs"
export PID_DIR="$RUN_DIR/run"

# Bind address:
#   "auto"     — auto-detect Tailscale IP (kalau Tailscale up), fallback 127.0.0.1.
#                Default dan rekomendasi — bind ke Tailscale IP biar HP bisa konek.
#   "127.0.0.1" — cuma localhost (HP gak bisa konek)
#   "0.0.0.0"   — bind ke semua interface (HP bisa konek tapi public internet juga bisa — RISIKO)
#   "100.x.x.x" — IP Tailscale eksplisit
export BIND_ADDR="auto"

# Path ke binary Chrome. Default: pake binary asli google-chrome-stable.
# Di sebagian environment (termasuk container Devin) ada wrapper "google-chrome"
# di PATH yang BUKAN binary asli. Pake path absolut biar gak ke-shim.
export CHROME_BIN="/usr/bin/google-chrome-stable"

# Chrome flags
export CHROME_FLAGS=(
  --no-first-run
  --no-default-browser-check
  --disable-background-networking
  --disable-features=Translate,InterestCohort
  --window-position=0,0
  --window-size=1280,800
  --start-maximized
  --no-sandbox  # sering dibutuhkan di VPS yang gak punya user namespaces; aman karena display terisolasi
)

# Telegram (opsional — kosongkan kalau gak pake)
export TELEGRAM_BOT_TOKEN=""
export TELEGRAM_CHAT_ID=""
EOF
  log "Default env.sh dibuat di $ENV_FILE — edit kalau perlu."
else
  log "env.sh sudah ada — skip generate."
fi

# Pastikan script lain executable
chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true

log "Install selesai."
echo
echo "================================================================"
echo "Langkah selanjutnya — Quick Test (5 menit):"
echo
echo "  1. Login Tailscale (sekali aja):"
echo "       sudo tailscale up"
echo "     Buka URL yang muncul di browser HP/laptop, login Google."
echo "     Install app Tailscale di HP juga, login akun Google yg sama."
echo
echo "  2. (Opsional) Cek semua dependency OK:"
echo "       $INSTALL_DIR/doctor.sh"
echo
echo "  3. Mulai stack:"
echo "       $INSTALL_DIR/start.sh"
echo "     Output bakal kasih: URL noVNC + password + command Hermes connect."
echo
echo "  4. (Kapan aja) Re-print info connection:"
echo "       $INSTALL_DIR/info.sh"
echo
echo "  5. Connect Hermes ke Chrome — di terminal Hermes:"
echo "       hermes chat"
echo "       /browser connect ws://127.0.0.1:9222"
echo
echo "  6. Buka URL noVNC di Chrome HP → liat & kontrol Chrome agent live."
echo
echo "================================================================"
