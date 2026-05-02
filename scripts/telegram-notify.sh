#!/usr/bin/env bash
# telegram-notify.sh — Kirim notifikasi ke Telegram saat captcha terdeteksi.
#
# Pemakaian:
#   ./telegram-notify.sh "Captcha terdeteksi!" [optional: path/to/screenshot.png]
#
# Konfigurasi: edit TELEGRAM_BOT_TOKEN dan TELEGRAM_CHAT_ID di scripts/env.sh
#
# Cara dapetin token & chat_id:
#   1. Bikin bot baru: chat ke @BotFather di Telegram, /newbot, ikutin instruksi → dapet TOKEN
#   2. Chat satu kali ke bot lu (start aja)
#   3. Buka: https://api.telegram.org/bot<TOKEN>/getUpdates → ambil "chat":{"id":...}
#   4. Isi di env.sh, save.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
. "$SCRIPT_DIR/env.sh"

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "[telegram] TELEGRAM_BOT_TOKEN atau TELEGRAM_CHAT_ID kosong — skip notif." >&2
  exit 0
fi

MESSAGE="${1:-Captcha terdeteksi! Buka VNC URL di HP buat takeover.}"
SCREENSHOT="${2:-}"

# Append URL VNC kalau Tailscale aktif
TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
if [[ -n "$TS_IP" ]]; then
  MESSAGE="$MESSAGE"$'\n\n'"VNC: http://$TS_IP:${NOVNC_PORT}/vnc.html?autoconnect=1&resize=remote"
fi

API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"

if [[ -n "$SCREENSHOT" && -f "$SCREENSHOT" ]]; then
  curl -sS -X POST "$API/sendPhoto" \
    -F "chat_id=$TELEGRAM_CHAT_ID" \
    -F "photo=@$SCREENSHOT" \
    -F "caption=$MESSAGE" >/dev/null
else
  curl -sS -X POST "$API/sendMessage" \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$MESSAGE" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null
fi

echo "[telegram] notif terkirim."
