#!/usr/bin/env bash
# new-instance.sh — Bikin instance baru biar bisa jalanin banyak agent paralel
# di mesin yg sama. Tiap instance punya RUN_DIR sendiri + Chrome profile sendiri
# + ports sendiri.
#
# Pemakaian:
#   ./new-instance.sh <name> [port_offset]
#
# Contoh:
#   ./new-instance.sh agent2 10
#   → bikin /opt/.../captcha-takeover-agent2/ dengan:
#       VNC_PORT=5911, NOVNC_PORT=6090, CHROME_CDP_PORT=9232
#       RUN_DIR=$HOME/.hermes-takeover-agent2
#
# Default offset 10 = port +10 (5911/6090/9232). Pilih offset yg cukup gede biar
# gak tabrakan (>=10 recommended).

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Pemakaian: $0 <instance-name> [port-offset]" >&2
  echo "Contoh:    $0 agent2 10" >&2
  exit 1
fi

NAME="$1"
OFFSET="${2:-10}"

# Validate name (filesystem-safe)
if [[ ! "$NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  echo "Error: nama instance harus lowercase + angka/dash/underscore aja (mis: agent2, scraper-1)" >&2
  exit 1
fi

if [[ ! "$OFFSET" =~ ^[0-9]+$ ]]; then
  echo "Error: port-offset harus angka" >&2
  exit 1
fi

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SRC_DIR")"
NEW_DIR="$PARENT_DIR/captcha-takeover-$NAME"

if [[ -e "$NEW_DIR" ]]; then
  echo "Error: $NEW_DIR udah ada. Hapus dulu atau pilih nama lain." >&2
  exit 1
fi

# Hitung ports baru
DEFAULT_VNC=5901
DEFAULT_NOVNC=6080
DEFAULT_CDP=9222
NEW_VNC=$((DEFAULT_VNC + OFFSET))
NEW_NOVNC=$((DEFAULT_NOVNC + OFFSET))
NEW_CDP=$((DEFAULT_CDP + OFFSET))

echo "Bikin instance '$NAME' di:"
echo "  Path        : $NEW_DIR"
echo "  RUN_DIR     : \$HOME/.hermes-takeover-$NAME"
echo "  VNC_PORT    : $NEW_VNC"
echo "  NOVNC_PORT  : $NEW_NOVNC"
echo "  CDP_PORT    : $NEW_CDP"
echo

# Copy seluruh tree (kecuali .git buat hemat)
cp -R "$SRC_DIR" "$NEW_DIR"
rm -rf "$NEW_DIR/.git"

# Edit env.sh instance baru
ENV_FILE="$NEW_DIR/scripts/env.sh"
sed -i \
  -e "s|^export VNC_PORT=\".*\"|export VNC_PORT=\"$NEW_VNC\"|" \
  -e "s|^export NOVNC_PORT=\".*\"|export NOVNC_PORT=\"$NEW_NOVNC\"|" \
  -e "s|^export CHROME_CDP_PORT=\".*\"|export CHROME_CDP_PORT=\"$NEW_CDP\"|" \
  -e "s|^export RUN_DIR=\".*\"|export RUN_DIR=\"\$HOME/.hermes-takeover-$NAME\"|" \
  -e "s|^export DISPLAY_NUM=\":1\"|export DISPLAY_NUM=\":$((1 + OFFSET))\"|" \
  "$ENV_FILE"

# Make scripts executable (gak ke-copy execute bit kadang)
chmod +x "$NEW_DIR"/*.sh "$NEW_DIR"/scripts/*.sh

echo "Selesai. Cara pake:"
echo
echo "  cd $NEW_DIR"
echo "  ./start.sh"
echo
echo "Connect agent #2 ke instance ini via:"
echo "  ws://127.0.0.1:$NEW_CDP"
echo
echo "noVNC URL bakal di port $NEW_NOVNC (cek output start.sh)"
