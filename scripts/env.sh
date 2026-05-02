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

# Bind address: pake 127.0.0.1 default. Kalau mau dari Tailscale only, ganti ke IP tailscale (cek `tailscale ip -4`)
# Dengan default ini, akses dari HP via Tailscale tetep works karena Tailscale sshuttle ke loopback.
# Kalau gak works, ganti ke "0.0.0.0" (kurang aman) atau IP tailscale spesifik.
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
