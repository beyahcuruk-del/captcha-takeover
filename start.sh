#!/usr/bin/env bash
# start.sh — Start the Hermes captcha takeover stack.
#
# Components started (background, with PID files):
#   1. Xvfb on $DISPLAY_NUM
#   2. fluxbox window manager
#   3. Google Chrome with remote debugging on $CHROME_CDP_PORT
#   4. x11vnc capturing $DISPLAY_NUM, listening on $VNC_PORT
#   5. websockify (noVNC) on $NOVNC_PORT bridging to VNC
#   6. watchdog (auto-restart Chrome on crash) — disable dgn START_WATCHDOG=0
#   7. (opsional) cloudflared quick tunnel — enable dgn TUNNEL_MODE=cloudflared

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { printf "${GREEN}[start]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[warn]${NC} %s\n" "$*"; }
die()  { printf "${RED}[error]${NC} %s\n" "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/scripts/env.sh"
[[ -f "$ENV_FILE" ]] || die "env.sh tidak ada. Run install.sh dulu."
# shellcheck disable=SC1090
. "$ENV_FILE"

mkdir -p "$LOG_DIR" "$PID_DIR" "$CHROME_USER_DATA_DIR"

# Auto-detect bind address: kalau BIND_ADDR=auto, pake Tailscale IP (kalau ada),
# kalau gak fallback 127.0.0.1.
if [[ "${BIND_ADDR:-auto}" == "auto" ]]; then
  TS_IP_AUTO="$(tailscale ip -4 2>/dev/null | head -1 || true)"
  if [[ -n "$TS_IP_AUTO" ]]; then
    BIND_ADDR="$TS_IP_AUTO"
    log "BIND_ADDR=auto → pake Tailscale IP $BIND_ADDR (akses dari HP via Tailscale)"
  else
    BIND_ADDR="127.0.0.1"
    warn "BIND_ADDR=auto, tapi Tailscale belum login — fallback ke 127.0.0.1 (cuma localhost). Run: sudo tailscale up"
  fi
fi

# Helper: start kalau belum jalan, simpan PID
start_bg() {
  local name="$1"; shift
  local pidfile="$PID_DIR/$name.pid"
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
    warn "$name sudah jalan (PID $(cat "$pidfile")) — skip."
    return 0
  fi
  log "Start $name..."
  ( setsid "$@" >>"$LOG_DIR/$name.log" 2>&1 < /dev/null & echo $! > "$pidfile" )
  sleep 0.5
  if ! kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    die "$name gagal start. Cek $LOG_DIR/$name.log"
  fi
  log "$name running (PID $(cat "$pidfile"))"
}

# 1) Xvfb
start_bg "xvfb" \
  Xvfb "$DISPLAY_NUM" -screen 0 "$SCREEN_GEOMETRY" -ac -nolisten tcp -dpi 96

# Tunggu sampai display siap
for _ in $(seq 1 30); do
  if DISPLAY="$DISPLAY_NUM" xdpyinfo >/dev/null 2>&1; then break; fi
  sleep 0.2
done
DISPLAY="$DISPLAY_NUM" xdpyinfo >/dev/null 2>&1 || die "Xvfb gak respond di $DISPLAY_NUM"

# 2) fluxbox (window manager — biar Chrome resizable & ada title bar)
start_bg "fluxbox" \
  env DISPLAY="$DISPLAY_NUM" fluxbox

# 3) Chrome dengan CDP
CHROME_BIN="${CHROME_BIN:-/usr/bin/google-chrome-stable}"
[[ -x "$CHROME_BIN" ]] || die "Chrome binary tidak ada di $CHROME_BIN. Edit CHROME_BIN di scripts/env.sh."

start_bg "chrome" \
  env DISPLAY="$DISPLAY_NUM" "$CHROME_BIN" \
    --remote-debugging-port="$CHROME_CDP_PORT" \
    --remote-debugging-address="127.0.0.1" \
    --user-data-dir="$CHROME_USER_DATA_DIR" \
    "${CHROME_FLAGS[@]}"

# Tunggu CDP siap
for _ in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:$CHROME_CDP_PORT/json/version" >/dev/null 2>&1; then break; fi
  sleep 0.3
done
curl -sf "http://127.0.0.1:$CHROME_CDP_PORT/json/version" >/dev/null 2>&1 \
  || warn "Chrome CDP belum respond di port $CHROME_CDP_PORT — cek $LOG_DIR/chrome.log"

# 4) x11vnc
[[ -f "$VNC_PASSWD_FILE" ]] || die "VNC password file tidak ada: $VNC_PASSWD_FILE — run install.sh"
start_bg "x11vnc" \
  x11vnc \
    -display "$DISPLAY_NUM" \
    -rfbport "$VNC_PORT" \
    -rfbauth "$VNC_PASSWD_FILE" \
    -listen "$BIND_ADDR" \
    -forever \
    -shared \
    -repeat \
    -nolookup \
    -noxdamage \
    -ncache 0

# 5) websockify (noVNC)
NOVNC_WEB="/usr/share/novnc"
[[ -d "$NOVNC_WEB" ]] || die "noVNC web dir tidak ada di $NOVNC_WEB. Install: sudo apt install novnc"

start_bg "websockify" \
  websockify \
    --web="$NOVNC_WEB" \
    "$BIND_ADDR:$NOVNC_PORT" \
    "127.0.0.1:$VNC_PORT"

# 6) Watchdog (auto-restart Chrome kalau crash). Optional — disable dgn START_WATCHDOG=0
if [[ "${START_WATCHDOG:-1}" != "0" ]]; then
  start_bg "watchdog" \
    bash "$SCRIPT_DIR/scripts/watchdog.sh"
fi

# 7) Optional tunnel mode (cloudflared quick tunnel — publik trycloudflare.com)
# Enable via TUNNEL_MODE=cloudflared di env.sh atau saat invocation:
#   TUNNEL_MODE=cloudflared ./start.sh
: > "$RUN_DIR/tunnel-url.txt" 2>/dev/null || true
case "${TUNNEL_MODE:-}" in
  cloudflared)
    if ! command -v cloudflared >/dev/null 2>&1; then
      warn "TUNNEL_MODE=cloudflared tapi cloudflared belum terinstall — skip. Install dgn ./install.sh atau lihat https://github.com/cloudflare/cloudflared/releases"
    else
      start_bg "cloudflared" \
        bash "$SCRIPT_DIR/scripts/tunnel-cloudflared.sh"
      # Tunggu URL muncul di file (max 20 detik)
      log "Nunggu cloudflared assign URL (max 20s)..."
      for _ in $(seq 1 40); do
        if [[ -s "$RUN_DIR/tunnel-url.txt" ]]; then break; fi
        sleep 0.5
      done
      if [[ -s "$RUN_DIR/tunnel-url.txt" ]]; then
        log "Tunnel URL: $(cat "$RUN_DIR/tunnel-url.txt")"
      else
        warn "Cloudflared belum assign URL setelah 20s — cek $LOG_DIR/cloudflared.log"
      fi
    fi
    ;;
  ""|none|localhost)
    : # no tunnel — default
    ;;
  *)
    warn "TUNNEL_MODE=$TUNNEL_MODE tidak dikenali. Pilihan: '' (default) atau 'cloudflared'."
    ;;
esac

# Info akhir — delegasiin ke info.sh biar konsisten
exec "$SCRIPT_DIR/info.sh"
