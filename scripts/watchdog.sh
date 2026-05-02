#!/usr/bin/env bash
# watchdog.sh — Background script yg restart Chrome kalau crash.
#
# Started by start.sh setelah semua komponen lain UP. Cek tiap CHECK_INTERVAL
# detik: kalau PID file Chrome ada tapi proses-nya gak running, restart Chrome
# pake parameter yg sama. Stop kalau xvfb mati (artinya stack di-stop bener).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1090
. "$SCRIPT_DIR/env.sh"

CHECK_INTERVAL="${WATCHDOG_INTERVAL:-10}"
MAX_RESTARTS="${WATCHDOG_MAX_RESTARTS:-20}"

log() { echo "[watchdog $(date +%H:%M:%S)] $*" >> "$LOG_DIR/watchdog.log"; }

is_running() {
  local pidfile="$1"
  [[ -f "$pidfile" ]] || return 1
  local pid
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

restart_chrome() {
  log "Chrome down. Restarting..."
  # Pakai flags yg sama kayak start.sh
  local user_data_dir="$CHROME_USER_DATA_DIR"
  local cdp_port="$CHROME_CDP_PORT"
  DISPLAY="$DISPLAY_NUM" \
    nohup "$CHROME_BIN" \
      "${CHROME_FLAGS[@]}" \
      --user-data-dir="$user_data_dir" \
      --remote-debugging-port="$cdp_port" \
      --remote-debugging-address=127.0.0.1 \
      "about:blank" \
      >> "$LOG_DIR/chrome.log" 2>&1 &
  echo $! > "$PID_DIR/chrome.pid"
  sleep 3
  if is_running "$PID_DIR/chrome.pid" && curl -sf "http://127.0.0.1:$cdp_port/json/version" >/dev/null 2>&1; then
    log "Chrome restarted OK (PID $(cat "$PID_DIR/chrome.pid"))."
    return 0
  else
    log "Chrome restart FAILED. Cek $LOG_DIR/chrome.log."
    return 1
  fi
}

mkdir -p "$LOG_DIR" "$PID_DIR"
log "Watchdog started (interval=${CHECK_INTERVAL}s max-restarts=${MAX_RESTARTS})"

restart_count=0
while true; do
  # Stop kalau xvfb mati (artinya user run stop.sh atau stack crash total)
  if ! is_running "$PID_DIR/xvfb.pid"; then
    log "xvfb mati — stack di-stop, watchdog exit."
    break
  fi

  if ! is_running "$PID_DIR/chrome.pid"; then
    if [[ "$restart_count" -ge "$MAX_RESTARTS" ]]; then
      log "Chrome mati lagi tapi udah $restart_count restart — give up. Cek log Chrome."
      sleep "$CHECK_INTERVAL"
      continue
    fi
    if restart_chrome; then
      restart_count=$((restart_count + 1))
    else
      sleep "$CHECK_INTERVAL"
    fi
  fi

  sleep "$CHECK_INTERVAL"
done

log "Watchdog exit."
