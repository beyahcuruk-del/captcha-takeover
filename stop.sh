#!/usr/bin/env bash
# stop.sh — Stop semua komponen takeover stack dengan rapih.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { printf "${GREEN}[stop]${NC} %s\n" "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/scripts/env.sh"
[[ -f "$ENV_FILE" ]] || { echo "env.sh missing"; exit 1; }
# shellcheck disable=SC1090
. "$ENV_FILE"

# Stop dalam urutan terbalik dari start
for name in websockify x11vnc chrome fluxbox xvfb; do
  pidfile="$PID_DIR/$name.pid"
  if [[ -f "$pidfile" ]]; then
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      log "Stopping $name (PID $pid)..."
      kill "$pid" 2>/dev/null || true
      # Tunggu graceful shutdown 3 detik
      for _ in 1 2 3 4 5 6; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
      done
      kill -9 "$pid" 2>/dev/null || true
    else
      printf "${YELLOW}[stop]${NC} %s tidak running.\n" "$name"
    fi
    rm -f "$pidfile"
  fi
done

# Cleanup lock file Xvfb yang nyangkut
rm -f "/tmp/.X${DISPLAY_NUM#:}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM#:}" 2>/dev/null || true

log "Semua komponen stopped."
