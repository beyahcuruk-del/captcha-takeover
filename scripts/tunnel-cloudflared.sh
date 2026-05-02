#!/usr/bin/env bash
# tunnel-cloudflared.sh — start a Cloudflare quick tunnel pointing at noVNC port.
#
# Spawns `cloudflared tunnel --url http://127.0.0.1:$NOVNC_PORT`, parses its
# stdout to extract the assigned `https://<random>.trycloudflare.com` URL, and
# writes that URL to $RUN_DIR/tunnel-url.txt so info.sh / agents can read it.
#
# This wrapper is meant to be launched as a background daemon by start.sh
# (`start_bg "cloudflared" bash scripts/tunnel-cloudflared.sh`). It runs
# foreground inside that daemon shell — start_bg handles backgrounding +
# pidfile + log redirect.
#
# IMPORTANT: trycloudflare quick tunnels are PUBLIC. Anyone with the URL can
# reach noVNC. The VNC password is the only auth — keep it strong (it's
# auto-generated at install time). For private setups, use Tailscale instead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/scripts/env.sh"
[[ -f "$ENV_FILE" ]] || { echo "env.sh missing at $ENV_FILE"; exit 1; }
# shellcheck disable=SC1090
. "$ENV_FILE"

URL_FILE="$RUN_DIR/tunnel-url.txt"
mkdir -p "$RUN_DIR"
: > "$URL_FILE"

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared tidak terinstall. Install dulu (lihat install.sh atau https://github.com/cloudflare/cloudflared/releases)." >&2
  exit 1
fi

# Trap supaya kalau script ini ke-kill, anak-anak (cloudflared) juga ikut mati.
cleanup() {
  local pids
  pids="$(jobs -p)"
  [[ -n "$pids" ]] && kill $pids 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[tunnel-cloudflared] starting quick tunnel for http://127.0.0.1:$NOVNC_PORT ..."

# Run cloudflared, fan stdout/stderr to our stdout AND scan for the trycloudflare URL.
# `stdbuf -oL` biar line-buffered (kalau coreutils ada).
CF_CMD=(cloudflared tunnel --url "http://127.0.0.1:$NOVNC_PORT" --no-autoupdate)
if command -v stdbuf >/dev/null 2>&1; then
  CF_CMD=(stdbuf -oL -eL "${CF_CMD[@]}")
fi

"${CF_CMD[@]}" 2>&1 | while IFS= read -r line; do
  printf '%s\n' "$line"
  if [[ "$line" =~ (https://[a-z0-9-]+\.trycloudflare\.com) ]]; then
    URL="${BASH_REMATCH[1]}"
    if [[ "$(cat "$URL_FILE" 2>/dev/null || true)" != "$URL" ]]; then
      printf '%s\n' "$URL" > "$URL_FILE"
      echo "[tunnel-cloudflared] tunnel URL: $URL"
    fi
  fi
done
