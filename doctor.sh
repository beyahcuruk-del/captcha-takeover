#!/usr/bin/env bash
# doctor.sh — Diagnose masalah umum sebelum/setelah start.sh.
# Ngecek: dependency installed, port free/used, Chrome bisa run, Tailscale state,
# Python deps importable, dan health endpoint.

set -uo pipefail   # gak pake -e biar lanjut walau ada check yg fail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { printf "  ${GREEN}[OK]${NC}   %s\n" "$*"; }
warn() { printf "  ${YELLOW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "  ${RED}[FAIL]${NC} %s\n" "$*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

FAIL_COUNT=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/scripts/env.sh"

printf "${BOLD}=== Captcha Takeover Doctor ===${NC}\n\n"

# 1. env.sh
printf "${BOLD}[1] Konfigurasi${NC}\n"
if [[ -f "$ENV_FILE" ]]; then
  ok "env.sh ada di $ENV_FILE"
  # shellcheck disable=SC1090
  . "$ENV_FILE"
else
  fail "env.sh gak ada di $ENV_FILE — run ./install.sh"
  exit 1
fi
echo

# 2. Binary requirements
printf "${BOLD}[2] Binary dependencies${NC}\n"
for cmd in Xvfb fluxbox x11vnc websockify curl jq python3 xdpyinfo import; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd ada"
  else
    fail "$cmd gak ada — run ./install.sh"
  fi
done

CHROME_BIN_RESOLVED="${CHROME_BIN:-/usr/bin/google-chrome-stable}"
if [[ -x "$CHROME_BIN_RESOLVED" ]]; then
  ok "Chrome binary: $CHROME_BIN_RESOLVED ($("$CHROME_BIN_RESOLVED" --version 2>/dev/null | head -1 || echo unknown))"
else
  fail "Chrome binary gak ada di $CHROME_BIN_RESOLVED"
  if dpkg -s google-chrome-stable >/dev/null 2>&1; then
    warn "google-chrome-stable terinstall via dpkg, tapi binary gak di $CHROME_BIN_RESOLVED — edit CHROME_BIN di env.sh"
  else
    warn "google-chrome-stable gak terinstall — run ./install.sh"
  fi
fi

if [[ -d /usr/share/novnc ]]; then
  ok "noVNC web dir: /usr/share/novnc"
else
  fail "noVNC web dir /usr/share/novnc gak ada — run: sudo apt install novnc"
fi
echo

# 3. Python deps
printf "${BOLD}[3] Python dependencies${NC}\n"
if python3 -c "import requests, websockets" 2>/dev/null; then
  ok "python3 has 'requests' and 'websockets'"
else
  fail "python3 gak punya 'requests' atau 'websockets'"
  warn "Install: python3 -m pip install --user --break-system-packages requests websockets"
fi
echo

# 4. Ports
printf "${BOLD}[4] Port usage${NC}\n"
check_port() {
  local port="$1" label="$2" pidfile="$3"
  local listener owner
  # Match column 4 ending with ":<port>" (handles "127.0.0.1:5902" and "[::]:5902")
  listener="$(ss -tlnp 2>/dev/null | awk -v p=":${port}\$" '$4 ~ p {print $0; exit}')"
  if [[ -z "$listener" ]]; then
    warn "$label (port $port) belum listening — kalau udah ./start.sh, mungkin component fail; cek log."
    return
  fi
  # Cek apakah pemegang port adalah proses kita (PID match dengan PID file)
  owner="$(echo "$listener" | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -1)"
  local our_pid=""
  [[ -n "$pidfile" && -f "$pidfile" ]] && our_pid="$(cat "$pidfile" 2>/dev/null)"
  if [[ -n "$our_pid" && "$owner" == "$our_pid" ]]; then
    ok "$label (port $port) LISTENING (process kita, PID $owner)"
  elif [[ -z "$our_pid" ]]; then
    fail "$label (port $port) udah dipake proses lain (PID $owner)! Stack belum start tapi port udah occupied. Edit ${label}_PORT di scripts/env.sh ke port lain, atau matiin proses yg occupy."
  else
    fail "$label (port $port) DIPAKE proses lain (PID $owner), bukan kita (PID $our_pid). Restart stack atau ganti port."
  fi
}

check_port "$VNC_PORT" "VNC" "$PID_DIR/x11vnc.pid"
check_port "$NOVNC_PORT" "noVNC" "$PID_DIR/websockify.pid"
check_port "$CHROME_CDP_PORT" "Chrome CDP" "$PID_DIR/chrome.pid"
echo

# 5. Components running
printf "${BOLD}[5] Component processes${NC}\n"
for name in xvfb fluxbox chrome x11vnc websockify watchdog; do
  pidfile="$PID_DIR/$name.pid"
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
    ok "$name running (PID $(cat "$pidfile"))"
  else
    warn "$name gak running"
  fi
done
echo

# 6. CDP responsive
printf "${BOLD}[6] Endpoint health${NC}\n"
if curl -sf "http://127.0.0.1:$CHROME_CDP_PORT/json/version" >/dev/null 2>&1; then
  ver="$(curl -sS "http://127.0.0.1:$CHROME_CDP_PORT/json/version" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Browser"])' 2>/dev/null || echo unknown)"
  ok "Chrome CDP responsive: $ver"
else
  warn "Chrome CDP gak respond di port $CHROME_CDP_PORT — cek $LOG_DIR/chrome.log"
fi

if curl -sf "http://127.0.0.1:$NOVNC_PORT/vnc.html" >/dev/null 2>&1; then
  ok "noVNC web responsive"
else
  warn "noVNC web gak respond di port $NOVNC_PORT — cek $LOG_DIR/websockify.log"
fi
echo

# 7. Tailscale
printf "${BOLD}[7] Tailscale${NC}\n"
if command -v tailscale >/dev/null 2>&1; then
  state="$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState","Unknown"))' 2>/dev/null || echo Unknown)"
  ts_ip="$(tailscale ip -4 2>/dev/null | head -1 || true)"
  case "$state" in
    Running)
      ok "Tailscale running (IP: $ts_ip)"
      ;;
    NeedsLogin|Stopped|"")
      warn "Tailscale belum login — run: sudo tailscale up"
      ;;
    *)
      warn "Tailscale state: $state"
      ;;
  esac
else
  warn "Tailscale gak terinstall — run ./install.sh"
fi
echo

# 8. BIND_ADDR sanity
printf "${BOLD}[8] BIND_ADDR sanity${NC}\n"
case "${BIND_ADDR:-auto}" in
  auto)
    if [[ -n "${ts_ip:-}" ]]; then
      ok "BIND_ADDR=auto + Tailscale up → akan bind ke $ts_ip"
    else
      warn "BIND_ADDR=auto tapi Tailscale belum up → akan fallback ke 127.0.0.1 (cuma localhost)"
    fi
    ;;
  127.0.0.1)
    warn "BIND_ADDR=127.0.0.1 → cuma bisa diakses dari VPS sendiri. Ganti ke 'auto' biar pake Tailscale."
    ;;
  0.0.0.0)
    warn "BIND_ADDR=0.0.0.0 → expose ke SEMUA interface termasuk public internet. Pake Tailscale lebih aman."
    ;;
  *)
    ok "BIND_ADDR=$BIND_ADDR (custom)"
    ;;
esac
echo

# Ringkasan
printf "${BOLD}=== Summary ===${NC}\n"
if [[ "$FAIL_COUNT" -eq 0 ]]; then
  printf "${GREEN}Semua check FAIL kosong. WARN-warn di atas optional.${NC}\n"
  exit 0
else
  printf "${RED}Ada %d FAIL. Fix dulu sebelum jalanin start.sh.${NC}\n" "$FAIL_COUNT"
  exit 1
fi
