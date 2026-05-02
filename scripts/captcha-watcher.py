#!/usr/bin/env python3
"""captcha-watcher.py — Detect captcha di Chrome (via CDP) lalu kirim notif Telegram.

Pemakaian:
    python3 scripts/captcha-watcher.py

Konfigurasi: scripts/env.sh (TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID).
Stop: Ctrl+C atau kirim SIGTERM.

Dependency: python3, python3-websockets (apt), python3-requests (apt). Install
otomatis lewat install.sh.
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

try:
    import requests
    import websockets
except ImportError as e:
    print(f"[captcha-watcher] missing dep: {e}. Install: sudo apt install python3-websockets python3-requests", file=sys.stderr)
    sys.exit(2)

# -- konfigurasi ------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
ENV_FILE = SCRIPT_DIR / "env.sh"


_VAR_RE = re.compile(r"\$\{?(\w+)\}?")


def _expand(value: str, ctx: dict[str, str]) -> str:
    """Expand $VAR and ${VAR} pakai ctx + os.environ (ctx menang)."""

    def sub(m: re.Match[str]) -> str:
        key = m.group(1)
        if key in ctx:
            return ctx[key]
        return os.environ.get(key, "")

    return _VAR_RE.sub(sub, value)


def _parse_env(path: Path) -> dict[str, str]:
    """Parse `KEY=VALUE` lines (dan `export KEY=VALUE`) dari file shell sederhana.

    Expand $VAR / ${VAR} pakai key sebelumnya + os.environ. Skip array literals.
    """
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :]
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        v = v.strip()
        # Skip array/multiline lines (mulai dgn '(' )
        if v.startswith("("):
            continue
        # Strip kutip atau komentar trailing
        if len(v) >= 2 and v[0] in ("'", '"') and v[-1] == v[0]:
            v = v[1:-1]
        else:
            v = v.split("#", 1)[0].strip()
        # Expand variabel sebelum simpan
        out[k.strip()] = _expand(v, out)
    return out


ENV = _parse_env(ENV_FILE)
# Override sama OS env (kalau user export manual)
ENV.update({k: v for k, v in os.environ.items() if k in ENV})

CDP_PORT = int(ENV.get("CHROME_CDP_PORT", "9222"))
NOVNC_PORT = int(ENV.get("NOVNC_PORT", "6080"))
DISPLAY_NUM = ENV.get("DISPLAY_NUM", ":1")
RUN_DIR = Path(ENV.get("RUN_DIR", str(Path.home() / ".hermes-takeover")))
LOG_DIR = Path(ENV.get("LOG_DIR", str(RUN_DIR / "logs")))
LOG_DIR.mkdir(parents=True, exist_ok=True)

POLL_INTERVAL = float(os.environ.get("POLL_INTERVAL", "5"))
COOLDOWN = float(os.environ.get("COOLDOWN", "120"))

TG_TOKEN = ENV.get("TELEGRAM_BOT_TOKEN", "")
TG_CHAT = ENV.get("TELEGRAM_CHAT_ID", "")

# JS detection — dijalanin di tiap tab Chrome
DETECT_JS = r"""(() => {
  const selectors = [
    'iframe[src*="recaptcha"]',
    'iframe[src*="hcaptcha"]',
    'iframe[src*="challenges.cloudflare.com"]',
    'div.g-recaptcha',
    'div.h-captcha',
    'div[class*="cf-turnstile"]',
    '#challenge-form',
    '#cf-challenge-running',
  ];
  for (const sel of selectors) {
    const el = document.querySelector(sel);
    if (el) {
      const r = el.getBoundingClientRect();
      // Hanya hitung kalau visible (size > 0)
      if (r.width > 0 && r.height > 0) return sel;
    }
  }
  return '';
})()"""


def log(msg: str) -> None:
    print(f"[captcha-watcher {time.strftime('%H:%M:%S')}] {msg}", flush=True)


def get_tailscale_ip() -> str:
    try:
        out = subprocess.run(
            ["tailscale", "ip", "-4"],
            capture_output=True,
            text=True,
            timeout=3,
        )
        return out.stdout.strip().splitlines()[0] if out.stdout.strip() else ""
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""


def take_screenshot() -> Path | None:
    shot = LOG_DIR / f"captcha-{time.strftime('%Y%m%d-%H%M%S')}.png"
    env = os.environ.copy()
    env["DISPLAY"] = DISPLAY_NUM
    try:
        r = subprocess.run(
            ["import", "-window", "root", str(shot)],
            env=env,
            capture_output=True,
            timeout=5,
        )
        if r.returncode == 0 and shot.is_file():
            return shot
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return None


EVENT_LOG = LOG_DIR / "captcha-events.log"


def append_event(message: str, screenshot: Path | None) -> None:
    """Tulis event ke log file biar tetep bisa di-tail walau tanpa Telegram."""
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {message.replace(chr(10), ' | ')}"
    if screenshot:
        line += f" | screenshot={screenshot}"
    line += "\n"
    try:
        with EVENT_LOG.open("a") as f:
            f.write(line)
    except OSError as e:
        log(f"Gagal tulis event log: {e}")


def send_telegram(message: str, screenshot: Path | None) -> None:
    # Selalu append ke event log dulu (independent dari Telegram).
    append_event(message, screenshot)
    if not TG_TOKEN or not TG_CHAT:
        log("Telegram belum di-set — event ditulis ke " + str(EVENT_LOG))
        return
    api = f"https://api.telegram.org/bot{TG_TOKEN}"
    try:
        if screenshot and screenshot.is_file():
            with screenshot.open("rb") as f:
                r = requests.post(
                    f"{api}/sendPhoto",
                    data={"chat_id": TG_CHAT, "caption": message},
                    files={"photo": f},
                    timeout=15,
                )
        else:
            r = requests.post(
                f"{api}/sendMessage",
                data={
                    "chat_id": TG_CHAT,
                    "text": message,
                    "disable_web_page_preview": "true",
                },
                timeout=15,
            )
        r.raise_for_status()
        log("Notif Telegram terkirim.")
    except requests.RequestException as e:
        log(f"Gagal kirim Telegram: {e}")


async def evaluate_in_tab(ws_url: str, expression: str) -> str:
    """Kirim Runtime.evaluate via CDP websocket, return string result."""
    try:
        async with websockets.connect(ws_url, max_size=2**20, open_timeout=3, close_timeout=2) as ws:
            payload = {
                "id": 1,
                "method": "Runtime.evaluate",
                "params": {"expression": expression, "returnByValue": True},
            }
            await ws.send(json.dumps(payload))
            # Tunggu pesan dengan id=1 (skip event lain)
            for _ in range(20):
                raw = await asyncio.wait_for(ws.recv(), timeout=3)
                msg = json.loads(raw)
                if msg.get("id") == 1:
                    return msg.get("result", {}).get("result", {}).get("value", "") or ""
            return ""
    except Exception:
        return ""


async def list_pages() -> list[dict]:
    try:
        r = requests.get(f"http://127.0.0.1:{CDP_PORT}/json", timeout=2)
        r.raise_for_status()
        return [t for t in r.json() if t.get("type") == "page" and t.get("webSocketDebuggerUrl")]
    except requests.RequestException:
        return []


def build_message(selector: str, page_url: str) -> str:
    msg = f"Captcha terdeteksi di Hermes browser!\nSelector: {selector}\nPage: {page_url}"
    ts_ip = get_tailscale_ip()
    if ts_ip:
        msg += f"\n\nVNC takeover: http://{ts_ip}:{NOVNC_PORT}/vnc.html?autoconnect=1&resize=remote"
    return msg


async def main() -> None:
    log(f"Start. CDP=127.0.0.1:{CDP_PORT} interval={POLL_INTERVAL}s cooldown={COOLDOWN}s")
    last_notif = 0.0

    stop = asyncio.Event()

    def _shutdown(*_: object) -> None:
        log("Shutdown...")
        stop.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _shutdown)
        except NotImplementedError:
            pass

    while not stop.is_set():
        # Cek CDP up
        pages = await list_pages()
        if not pages:
            try:
                await asyncio.wait_for(stop.wait(), timeout=POLL_INTERVAL)
            except asyncio.TimeoutError:
                pass
            continue

        if time.time() - last_notif < COOLDOWN:
            try:
                await asyncio.wait_for(stop.wait(), timeout=POLL_INTERVAL)
            except asyncio.TimeoutError:
                pass
            continue

        for page in pages:
            sel = await evaluate_in_tab(page["webSocketDebuggerUrl"], DETECT_JS)
            if sel:
                page_url = page.get("url", "")
                log(f"DETECTED captcha (selector={sel}) di {page_url}")
                shot = take_screenshot()
                send_telegram(build_message(sel, page_url), shot)
                last_notif = time.time()
                break

        try:
            await asyncio.wait_for(stop.wait(), timeout=POLL_INTERVAL)
        except asyncio.TimeoutError:
            pass

    log("Bye.")


if __name__ == "__main__":
    asyncio.run(main())
