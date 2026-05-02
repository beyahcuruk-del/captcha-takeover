#!/usr/bin/env bash
# watch-captcha.sh — Convenience wrapper buat jalanin captcha watcher di background.
#
# Pemakaian:
#   ./watch-captcha.sh start     # jalanin di background
#   ./watch-captcha.sh stop      # stop
#   ./watch-captcha.sh status    # cek status
#   ./watch-captcha.sh logs      # tail log
#   ./watch-captcha.sh foreground # jalanin di foreground (debug)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/scripts/env.sh"
[[ -f "$ENV_FILE" ]] || { echo "env.sh missing — run install.sh dulu"; exit 1; }
# shellcheck disable=SC1090
. "$ENV_FILE"

PY="$SCRIPT_DIR/scripts/captcha-watcher.py"
PIDFILE="$PID_DIR/captcha-watcher.pid"
LOGFILE="$LOG_DIR/captcha-watcher.log"
mkdir -p "$PID_DIR" "$LOG_DIR"

cmd="${1:-status}"
case "$cmd" in
  start)
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "Sudah jalan (PID $(cat "$PIDFILE"))"
      exit 0
    fi
    setsid python3 "$PY" >>"$LOGFILE" 2>&1 < /dev/null &
    echo $! > "$PIDFILE"
    sleep 0.5
    if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "Captcha watcher started (PID $(cat "$PIDFILE")). Log: $LOGFILE"
    else
      echo "Gagal start. Cek $LOGFILE"
      exit 1
    fi
    ;;
  stop)
    if [[ -f "$PIDFILE" ]]; then
      pid="$(cat "$PIDFILE")"
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
      rm -f "$PIDFILE"
      echo "Stopped."
    else
      echo "Belum running."
    fi
    ;;
  status)
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "UP (PID $(cat "$PIDFILE"))"
    else
      echo "OFF"
    fi
    ;;
  logs)
    tail -f "$LOGFILE"
    ;;
  foreground|fg)
    exec python3 "$PY"
    ;;
  *)
    echo "Usage: $0 {start|stop|status|logs|foreground}"
    exit 1
    ;;
esac
