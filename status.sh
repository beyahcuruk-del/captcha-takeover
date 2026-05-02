#!/usr/bin/env bash
# status.sh — Cek status komponen.
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/scripts/env.sh"
# shellcheck disable=SC1090
. "$ENV_FILE"

# Resolve BIND_ADDR=auto same way as start.sh / info.sh
if [[ "${BIND_ADDR:-auto}" == "auto" ]]; then
  TS_IP_AUTO="$(tailscale ip -4 2>/dev/null | head -1 || true)"
  if [[ -n "$TS_IP_AUTO" ]]; then
    BIND_ADDR="$TS_IP_AUTO"
  else
    BIND_ADDR="127.0.0.1"
  fi
fi

echo "=== Captcha Takeover Status ==="
for name in xvfb fluxbox chrome x11vnc websockify; do
  pidfile="$PID_DIR/$name.pid"
  if [[ -f "$pidfile" ]]; then
    pid="$(cat "$pidfile")"
    if kill -0 "$pid" 2>/dev/null; then
      printf "  ${GREEN}[UP]${NC}   %-12s PID=%s\n" "$name" "$pid"
    else
      printf "  ${RED}[DEAD]${NC} %-12s (stale PID %s)\n" "$name" "$pid"
    fi
  else
    printf "  ${YELLOW}[OFF]${NC}  %-12s\n" "$name"
  fi
done

echo
echo "=== Endpoints ==="
printf "  Chrome CDP : http://127.0.0.1:%s/json/version  " "$CHROME_CDP_PORT"
if curl -sf "http://127.0.0.1:$CHROME_CDP_PORT/json/version" >/dev/null 2>&1; then
  printf "${GREEN}OK${NC}\n"
else
  printf "${RED}DOWN${NC}\n"
fi

printf "  noVNC      : http://%s:%s/vnc.html  " "$BIND_ADDR" "$NOVNC_PORT"
if curl -sf "http://$BIND_ADDR:$NOVNC_PORT/" >/dev/null 2>&1; then
  printf "${GREEN}OK${NC}\n"
else
  printf "${RED}DOWN${NC}\n"
fi

echo
echo "=== Tailscale ==="
if command -v tailscale >/dev/null 2>&1; then
  TS_STATUS="$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "Unknown"' 2>/dev/null || echo Unknown)"
  TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || echo "-")"
  echo "  State: $TS_STATUS"
  echo "  IP   : $TS_IP"
  if [[ "$TS_IP" != "-" ]]; then
    PASS="$(cat "$RUN_DIR/vncpasswd.txt" 2>/dev/null || echo "(cek $RUN_DIR/vncpasswd.txt)")"
    echo
    echo "  URL untuk HP:"
    echo "    http://$TS_IP:$NOVNC_PORT/vnc.html?autoconnect=1&resize=remote"
    echo "    Password: $PASS"
  fi
else
  echo "  tailscale tidak terinstall."
fi
