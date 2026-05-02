#!/usr/bin/env bash
# info.sh — Print noVNC URL + agent connect commands, copy-paste ready.
# Also writes machine-readable info to $RUN_DIR/info.json so agents can
# read connection info programmatically. Use --json to print JSON to stdout.

set -euo pipefail
JSON_MODE="${1:-}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/scripts/env.sh"
[[ -f "$ENV_FILE" ]] || { echo "env.sh gak ada — run install.sh dulu." >&2; exit 1; }
# shellcheck disable=SC1090
. "$ENV_FILE"

# Resolve BIND_ADDR=auto sama kayak start.sh
if [[ "${BIND_ADDR:-auto}" == "auto" ]]; then
  TS_IP_AUTO="$(tailscale ip -4 2>/dev/null | head -1 || true)"
  if [[ -n "$TS_IP_AUTO" ]]; then
    BIND_ADDR="$TS_IP_AUTO"
  else
    BIND_ADDR="127.0.0.1"
  fi
fi

TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || echo "")"
TS_STATE="$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("BackendState","Unknown"))' 2>/dev/null || echo "Unknown")"
VNC_PASS="$(cat "${VNC_PASSWD_FILE}.txt" 2>/dev/null || cat "$RUN_DIR/vncpasswd.txt" 2>/dev/null || echo "(cek $RUN_DIR/vncpasswd.txt)")"

# Pilih host buat URL: prefer Tailscale IP kalau ada, fallback BIND_ADDR
if [[ -n "$TS_IP" ]]; then
  HOST="$TS_IP"
  ACCESS_HINT="dari HP/laptop via Tailscale (HP juga harus install Tailscale + login akun yg sama)"
else
  HOST="$BIND_ADDR"
  if [[ "$HOST" == "127.0.0.1" ]]; then
    ACCESS_HINT="HANYA dari mesin VPS ini sendiri. Buat akses dari HP, run: sudo tailscale up"
  else
    ACCESS_HINT="dari device lain di network yang sama"
  fi
fi

NOVNC_URL_AUTH="http://${HOST}:${NOVNC_PORT}/vnc.html?autoconnect=1&resize=remote&password=${VNC_PASS}"
NOVNC_URL_PROMPT="http://${HOST}:${NOVNC_PORT}/vnc.html?autoconnect=1&resize=remote"
CDP_HTTP="http://127.0.0.1:${CHROME_CDP_PORT}"
CDP_ADDR="127.0.0.1:${CHROME_CDP_PORT}"
CDP_WS="ws://127.0.0.1:${CHROME_CDP_PORT}"

# Always write machine-readable info.json (agents can read this)
INFO_JSON="$RUN_DIR/info.json"
mkdir -p "$RUN_DIR"
cat > "$INFO_JSON" <<EOF
{
  "novnc_url": "$NOVNC_URL_AUTH",
  "novnc_url_no_password": "$NOVNC_URL_PROMPT",
  "vnc_password": "$VNC_PASS",
  "vnc_addr": "${HOST}:${VNC_PORT}",
  "cdp_http": "$CDP_HTTP",
  "cdp_addr": "$CDP_ADDR",
  "cdp_ws": "$CDP_WS",
  "tailscale_ip": "$TS_IP",
  "tailscale_state": "$TS_STATE",
  "bind_addr": "$BIND_ADDR",
  "host_for_remote_access": "$HOST"
}
EOF
chmod 600 "$INFO_JSON"

if [[ "$JSON_MODE" == "--json" ]]; then
  cat "$INFO_JSON"
  exit 0
fi

echo
printf "${CYAN}================================================================${NC}\n"
printf "${BOLD}${GREEN}Captcha Takeover — siap dipake${NC}\n"
printf "${CYAN}================================================================${NC}\n\n"

printf "${BOLD}1) Connect Hermes ke Chrome${NC} (di terminal VPS atau mesin lain yg ada Hermes):\n"
printf "   ${GREEN}hermes chat${NC}\n"
printf "   Lalu di prompt Hermes, ketik:\n"
printf "   ${GREEN}/browser connect ws://127.0.0.1:%s${NC}\n\n" "$CHROME_CDP_PORT"
printf "   Kalau Hermes jalan di mesin lain (laptop, dll), ganti ${YELLOW}127.0.0.1${NC} jadi:\n"
printf "   ${GREEN}ws://%s:%s${NC}  (set BIND_ADDR di env.sh ke 0.0.0.0 atau IP Tailscale, restart)\n\n" "$HOST" "$CHROME_CDP_PORT"

printf "${BOLD}2) Buka noVNC viewer di Chrome HP/laptop${NC} ($ACCESS_HINT):\n"
printf "   ${GREEN}%s${NC}\n\n" "$NOVNC_URL_AUTH"
printf "   (atau tanpa auto-password buat lebih aman):\n"
printf "   ${GREEN}%s${NC}\n" "$NOVNC_URL_PROMPT"
printf "   ${BOLD}VNC password:${NC} ${YELLOW}%s${NC}\n\n" "$VNC_PASS"

printf "${BOLD}3) Workflow takeover captcha:${NC}\n"
printf "   - Hermes navigate ke website biasa\n"
printf "   - Pas captcha muncul, Hermes biasanya stuck\n"
printf "   - Lu buka URL noVNC di HP, klik captcha pake jari\n"
printf "   - Hermes auto lanjut\n\n"

printf "${BOLD}Status komponen:${NC}\n"
"$SCRIPT_DIR/status.sh" 2>/dev/null | sed -n '/^=== Captcha Takeover/,/^=== Endpoints ===/p' | grep -v "^=== Endpoints" || true

printf "\n${BOLD}Tailscale:${NC} %s" "$TS_STATE"
if [[ -n "$TS_IP" ]]; then
  printf " (IP: %s)\n" "$TS_IP"
else
  printf " — ${YELLOW}belum login${NC}. Run: sudo tailscale up\n"
fi

printf "\n${BOLD}Optional:${NC} notif captcha otomatis ke Telegram \u2014 set TELEGRAM_BOT_TOKEN & TELEGRAM_CHAT_ID di scripts/env.sh, lalu jalanin: ./watch-captcha.sh start\n"

printf "${CYAN}================================================================${NC}\n"
