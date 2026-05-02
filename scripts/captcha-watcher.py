#!/usr/bin/env python3
"""captcha-watcher.py — Detect captcha di Chrome (via CDP) lalu kirim notif.

Pemakaian:
    python3 scripts/captcha-watcher.py

Konfigurasi: scripts/env.sh.

Notification channels (semua optional, set environment variable / env.sh):
    Telegram:  TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
    ntfy.sh:   NTFY_TOPIC                (e.g. "myhermes-x9k3pm")
               NTFY_SERVER               (default https://ntfy.sh)
               NTFY_TOKEN                (optional bearer token)
    Discord:   DISCORD_WEBHOOK_URL       (full webhook URL)
    Slack:     SLACK_WEBHOOK_URL         (full incoming-webhook URL)
    Email:     SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS,
               SMTP_FROM, SMTP_TO        (comma-separated for multiple)

Yang gak di-set bakal di-skip. Kalau gak ada satupun yg di-set, event tetep
ditulis ke ~/.hermes-takeover/logs/captcha-events.log + screenshot.

Stop: Ctrl+C atau kirim SIGTERM.

Dependency: python3, python3-websockets, python3-requests. Install otomatis
lewat install.sh.
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import signal
import smtplib
import subprocess
import sys
import time
from email.message import EmailMessage
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
DETECT_JS_FILE = SCRIPT_DIR / "detect-captcha.js"


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
        # Kalau dimulai dgn quote, ambil sampai matching quote (handle inline comment).
        if v and v[0] in ("'", '"'):
            quote = v[0]
            end = v.find(quote, 1)
            if end >= 0:
                v = v[1:end]
            else:
                v = v[1:]  # unterminated; ambil sisanya
        else:
            # Strip inline comment & whitespace.
            v = v.split("#", 1)[0].strip()
        # Expand variabel sebelum simpan
        out[k.strip()] = _expand(v, out)
    return out


ENV = _parse_env(ENV_FILE)
# Override sama OS env (kalau user export manual)
ENV.update({k: v for k, v in os.environ.items() if k in ENV})


def cfg(key: str, default: str = "") -> str:
    """Get config value from env.sh, OS env taking precedence."""
    return os.environ.get(key, ENV.get(key, default))


CDP_PORT = int(cfg("CHROME_CDP_PORT", "9222"))
NOVNC_PORT = int(cfg("NOVNC_PORT", "6080"))
DISPLAY_NUM = cfg("DISPLAY_NUM", ":1")
RUN_DIR = Path(cfg("RUN_DIR", str(Path.home() / ".hermes-takeover")))
LOG_DIR = Path(cfg("LOG_DIR", str(RUN_DIR / "logs")))
LOG_DIR.mkdir(parents=True, exist_ok=True)

POLL_INTERVAL = float(os.environ.get("POLL_INTERVAL", "5"))
COOLDOWN = float(os.environ.get("COOLDOWN", "120"))

# Detection JS — load dari file (single source of truth, sama yg dipake agent)
if DETECT_JS_FILE.is_file():
    DETECT_JS = DETECT_JS_FILE.read_text()
else:
    # Fallback minimal kalau file gak ada (shouldn't happen pasca install)
    DETECT_JS = (
        "(() => {const sels=['iframe[src*=\"recaptcha\"]','iframe[src*=\"hcaptcha\"]',"
        "'div[class*=\"cf-turnstile\"]'];for(const s of sels)if(document.querySelector(s))"
        "return 'fallback:'+s;return null;})()"
    )


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


def get_takeover_url() -> str:
    """URL noVNC yg bisa dipake user. Prefer Tailscale IP, fallback ke info.json."""
    info_path = RUN_DIR / "info.json"
    if info_path.is_file():
        try:
            data = json.loads(info_path.read_text())
            if data.get("novnc_url"):
                return data["novnc_url"]
        except (json.JSONDecodeError, OSError):
            pass
    ts = get_tailscale_ip()
    host = ts or "127.0.0.1"
    return f"http://{host}:{NOVNC_PORT}/vnc.html?autoconnect=1&resize=remote"


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


# -- notification dispatcher ------------------------------------------------

EVENT_LOG = LOG_DIR / "captcha-events.log"


def append_event(message: str, screenshot: Path | None) -> None:
    """Tulis event ke log file biar tetep bisa di-tail walau tanpa notif channel."""
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


def notify_telegram(message: str, screenshot: Path | None) -> bool:
    token = cfg("TELEGRAM_BOT_TOKEN")
    chat = cfg("TELEGRAM_CHAT_ID")
    if not token or not chat:
        return False
    api = f"https://api.telegram.org/bot{token}"
    try:
        if screenshot and screenshot.is_file():
            with screenshot.open("rb") as f:
                r = requests.post(
                    f"{api}/sendPhoto",
                    data={"chat_id": chat, "caption": message},
                    files={"photo": f},
                    timeout=15,
                )
        else:
            r = requests.post(
                f"{api}/sendMessage",
                data={"chat_id": chat, "text": message, "disable_web_page_preview": "true"},
                timeout=15,
            )
        r.raise_for_status()
        log("Notif Telegram terkirim.")
        return True
    except requests.RequestException as e:
        log(f"Telegram gagal: {e}")
        return False


def notify_ntfy(message: str, screenshot: Path | None) -> bool:
    topic = cfg("NTFY_TOPIC")
    if not topic:
        return False
    server = cfg("NTFY_SERVER", "https://ntfy.sh").rstrip("/")
    token = cfg("NTFY_TOKEN")
    headers = {"Title": "Captcha Takeover", "Priority": "high", "Tags": "warning"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        # Kirim text dulu (URL ada di message body)
        r = requests.post(
            f"{server}/{topic}",
            data=message.encode("utf-8"),
            headers=headers,
            timeout=10,
        )
        r.raise_for_status()
        # Attach screenshot kalau ada (ntfy support file attachments)
        if screenshot and screenshot.is_file():
            with screenshot.open("rb") as f:
                r2 = requests.put(
                    f"{server}/{topic}",
                    data=f.read(),
                    headers={
                        **headers,
                        "Filename": screenshot.name,
                        "Title": "Captcha screenshot",
                    },
                    timeout=15,
                )
                r2.raise_for_status()
        log(f"Notif ntfy terkirim ke {server}/{topic}.")
        return True
    except requests.RequestException as e:
        log(f"ntfy gagal: {e}")
        return False


def notify_discord(message: str, screenshot: Path | None) -> bool:
    url = cfg("DISCORD_WEBHOOK_URL")
    if not url:
        return False
    try:
        if screenshot and screenshot.is_file():
            with screenshot.open("rb") as f:
                r = requests.post(
                    url,
                    data={"content": message},
                    files={"file": (screenshot.name, f, "image/png")},
                    timeout=15,
                )
        else:
            r = requests.post(url, json={"content": message}, timeout=10)
        r.raise_for_status()
        log("Notif Discord terkirim.")
        return True
    except requests.RequestException as e:
        log(f"Discord gagal: {e}")
        return False


def notify_slack(message: str, screenshot: Path | None) -> bool:
    url = cfg("SLACK_WEBHOOK_URL")
    if not url:
        return False
    try:
        # Slack incoming-webhook gak support file upload — cuma text. URL noVNC
        # masuk ke message body.
        r = requests.post(url, json={"text": message}, timeout=10)
        r.raise_for_status()
        log("Notif Slack terkirim.")
        return True
    except requests.RequestException as e:
        log(f"Slack gagal: {e}")
        return False


def notify_email(message: str, screenshot: Path | None) -> bool:
    host = cfg("SMTP_HOST")
    if not host:
        return False
    port = int(cfg("SMTP_PORT", "587"))
    user = cfg("SMTP_USER")
    password = cfg("SMTP_PASS")
    sender = cfg("SMTP_FROM", user)
    recipients = [a.strip() for a in cfg("SMTP_TO").split(",") if a.strip()]
    if not (sender and recipients):
        return False
    msg = EmailMessage()
    msg["From"] = sender
    msg["To"] = ", ".join(recipients)
    msg["Subject"] = "[Captcha Takeover] Captcha terdeteksi"
    msg.set_content(message)
    if screenshot and screenshot.is_file():
        with screenshot.open("rb") as f:
            msg.add_attachment(
                f.read(),
                maintype="image",
                subtype="png",
                filename=screenshot.name,
            )
    try:
        if port == 465:
            srv = smtplib.SMTP_SSL(host, port, timeout=15)
        else:
            srv = smtplib.SMTP(host, port, timeout=15)
            srv.ehlo()
            try:
                srv.starttls()
                srv.ehlo()
            except smtplib.SMTPException:
                pass  # plaintext SMTP server
        if user and password:
            srv.login(user, password)
        srv.send_message(msg)
        srv.quit()
        log(f"Notif email terkirim ke {len(recipients)} alamat.")
        return True
    except (smtplib.SMTPException, OSError) as e:
        log(f"Email gagal: {e}")
        return False


def dispatch(message: str, screenshot: Path | None) -> None:
    """Dispatch ke semua channel yg di-set. Selalu append ke event log."""
    append_event(message, screenshot)
    sent_any = False
    for fn in (notify_telegram, notify_ntfy, notify_discord, notify_slack, notify_email):
        if fn(message, screenshot):
            sent_any = True
    if not sent_any:
        log(
            "Belum ada notif channel di-set (Telegram/ntfy/Discord/Slack/email) — "
            f"event ditulis ke {EVENT_LOG}"
        )


# -- CDP polling ------------------------------------------------------------


async def evaluate_in_tab(ws_url: str, expression: str) -> str:
    """Kirim Runtime.evaluate via CDP websocket, return string result (or '')."""
    try:
        async with websockets.connect(ws_url, max_size=2**20, open_timeout=3, close_timeout=2) as ws:
            payload = {
                "id": 1,
                "method": "Runtime.evaluate",
                "params": {"expression": expression, "returnByValue": True},
            }
            await ws.send(json.dumps(payload))
            for _ in range(20):
                raw = await asyncio.wait_for(ws.recv(), timeout=3)
                msg = json.loads(raw)
                if msg.get("id") == 1:
                    val = msg.get("result", {}).get("result", {}).get("value")
                    return val if isinstance(val, str) else ""
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


def build_message(detection: str, page_url: str) -> str:
    msg = f"Captcha terdeteksi di Hermes/agent browser!\nDetection: {detection}\nPage: {page_url}"
    msg += f"\n\nVNC takeover: {get_takeover_url()}"
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
                log(f"DETECTED captcha ({sel}) di {page_url}")
                shot = take_screenshot()
                dispatch(build_message(sel, page_url), shot)
                last_notif = time.time()
                break

        try:
            await asyncio.wait_for(stop.wait(), timeout=POLL_INTERVAL)
        except asyncio.TimeoutError:
            pass

    log("Bye.")


if __name__ == "__main__":
    asyncio.run(main())
