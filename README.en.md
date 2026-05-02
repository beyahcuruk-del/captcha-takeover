# Captcha Takeover Skill

Lets a human user manually solve CAPTCHAs (reCAPTCHA, hCaptcha, Cloudflare
Turnstile, Arkose, GeeTest, DataDome, PerimeterX, Akamai, Imperva, Kasada, AWS
WAF, Lemin) when an autonomous browser agent gets blocked. Works framework-
agnostic with **Hermes Agent, Playwright, Puppeteer, Selenium, raw CDP** —
anything that speaks Chrome DevTools Protocol.

The agent runs in a VPS, you watch and click from your phone.

> Bahasa Indonesia version: see [README.md](./README.md).

## Quick start (3 minutes on your VPS — cloudflared, no Tailscale)

```bash
git clone https://github.com/beyahcuruk-del/captcha-takeover.git
cd captcha-takeover
chmod +x *.sh scripts/*.sh
./install.sh

# Start the stack with a Cloudflare quick tunnel — instant public HTTPS URL
TUNNEL_MODE=cloudflared ./start.sh
# → prints a https://<random>.trycloudflare.com/vnc.html?... URL + the
#   Chrome CDP URL ready to paste into your agent

# Open the trycloudflare.com URL on your phone's browser
```

In your agent, connect to Chrome over CDP at `http://127.0.0.1:9222`. When
the agent hits a CAPTCHA, your phone is already showing the page — just tap
through it and the agent continues.

## Tunnel options — how your phone reaches noVNC

By default noVNC binds to `127.0.0.1:6080`, which is only reachable from the
VPS itself. To open it from a phone you need one of these:

| Mode | How to start | URL the user gets | Privacy |
|------|--------------|--------------------|---------|
| **Cloudflared quick tunnel** ⚡ fastest | `TUNNEL_MODE=cloudflared ./start.sh` | `https://<random>.trycloudflare.com/...` | **Public** — anyone with the URL can connect; the VNC password is the only auth. Auto-rotates each restart. No account needed. |
| **Tailscale** 🔒 most private | `sudo tailscale up` once + install Tailscale app on phone, then `./start.sh` | `http://100.x.y.z:6080/...` | **Private VPN** — only your own devices can reach it. |
| **SSH local-forward** | `ssh -L 6080:127.0.0.1:6080 user@vps` and open `http://127.0.0.1:6080/...` on the laptop | localhost on laptop | Private, but laptop-only (won't work from phone over LTE) |
| None | plain `./start.sh` (no flag) | `http://127.0.0.1:6080/...` | Local only |

Recommendation:
- **One-off / quick demo** → cloudflared quick tunnel
- **Daily use** → Tailscale (more private, 2-minute one-time setup, then auto)

## Helper scripts

| Script | What it does |
|--------|--------------|
| `./install.sh` | Install all deps (Xvfb, Chrome, Tailscale, Python deps, etc.) |
| `./start.sh` | Start the stack (Xvfb + fluxbox + Chrome + x11vnc + websockify + watchdog) |
| `./stop.sh` | Stop everything cleanly |
| `./status.sh` | Component up/down + endpoint health |
| `./doctor.sh` | Diagnose dependency / port / health issues |
| `./info.sh` | Print noVNC URL and Chrome CDP URL (with `--json` flag for machine-readable output) |
| `./watch-captcha.sh` | Run the captcha watcher (auto-notifies when one appears) |
| `./new-instance.sh <name> <port-offset>` | Spawn a second isolated instance (multi-agent setups) |

## How it works

```
Your agent (any framework)
   ↓ connects via CDP to ws://127.0.0.1:9222
Google Chrome
   ↓ renders into
Xvfb display :1 (virtual screen)
   ↓ x11vnc captures
VNC server (port 5901)
   ↓ websockify + noVNC
HTTP server (port 6080) — accessible from phone browser
   ↓
Tailscale (private VPN between your devices)
   ↓
You on phone → tap CAPTCHA → agent unblocks
```

## Agent integration

Read `SKILL.md` for the agent-facing playbook. Per-framework copy-paste
examples in [`examples/`](./examples/):

| Framework | File |
|-----------|------|
| Hermes (Nous Research) | [`examples/hermes.md`](./examples/hermes.md) |
| Playwright (Python + Node) | [`examples/playwright.md`](./examples/playwright.md) |
| Puppeteer | [`examples/puppeteer.md`](./examples/puppeteer.md) |
| Selenium 4 | [`examples/selenium.md`](./examples/selenium.md) |
| Raw CDP | [`examples/manual-cdp.md`](./examples/manual-cdp.md) |

The detection logic is a single drop-in JS snippet:
[`scripts/detect-captcha.js`](./scripts/detect-captcha.js). Use it via
`page.evaluate()` (Playwright/Puppeteer) or `Runtime.evaluate` (raw CDP). It
returns `"vendor:selector"` (e.g. `"hcaptcha:iframe[src*=\"hcaptcha\"]"`) when
a challenge is on screen, `null` otherwise.

After the stack is running, the agent reads connection details from
`~/.hermes-takeover/info.json`:

```json
{
  "novnc_url": "http://100.x.x.x:6080/vnc.html?autoconnect=1&resize=remote&password=...",
  "cdp_http": "http://127.0.0.1:9222",
  "cdp_addr": "127.0.0.1:9222",
  "cdp_ws":   "ws://127.0.0.1:9222",
  "vnc_password": "...",
  "tailscale_ip": "100.x.x.x",
  "bind_addr": "127.0.0.1",
  "host_for_remote_access": "100.x.x.x"
}
```

## Notification channels (optional)

The watcher pings you when a CAPTCHA appears. Configure any subset in
`scripts/env.sh`; events are also always written to
`~/.hermes-takeover/logs/captcha-events.log`.

| Channel | Variables |
|---------|-----------|
| Telegram | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` |
| ntfy.sh | `NTFY_TOPIC` (and optionally `NTFY_SERVER`, `NTFY_TOKEN`) |
| Discord | `DISCORD_WEBHOOK_URL` |
| Slack | `SLACK_WEBHOOK_URL` |
| Email | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`, `SMTP_TO` |

Then run `./watch-captcha.sh start` (or just `python3 scripts/captcha-watcher.py`).

## Multi-instance (multiple agents on one VPS)

```bash
./new-instance.sh agent2 10
# Creates ../captcha-takeover-agent2/ with VNC=5911, noVNC=6090, CDP=9232
cd ../captcha-takeover-agent2
./start.sh
```

Each instance has its own `RUN_DIR`, Chrome profile, port set, and X display.

## Auto-restart on Chrome crash

`start.sh` launches a watchdog (PID file `watchdog.pid`) that polls Chrome
every 10s and restarts it if it dies while the rest of the stack is up.
Disable with `START_WATCHDOG=0 ./start.sh`. Tunable via env vars
`WATCHDOG_INTERVAL` (default 10) and `WATCHDOG_MAX_RESTARTS` (default 20).

## Auto-start at boot (optional, systemd)

```bash
sed -i "s/USER/$(whoami)/g" systemd/hermes-takeover.service
sudo cp systemd/hermes-takeover.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-takeover.service
```

## Troubleshooting

Run `./doctor.sh` first — it checks dependencies, ports, component PIDs,
endpoint health, and Tailscale state, and tells you what's wrong.

Common issues:

- **Phone can't reach noVNC URL** — make sure Tailscale is active on your
  phone (green checkmark in the app) and on the VPS (`tailscale status`).
  Bind to the Tailscale IP explicitly by setting `BIND_ADDR` in
  `scripts/env.sh` if `auto` doesn't pick it up.
- **Chrome won't start** — check `~/.hermes-takeover/logs/chrome.log`. On
  VPSes with <1 GB RAM, Chrome may OOM; add swap or upgrade.
- **Port already in use** — `doctor.sh` will tell you which PID has the port
  and which port to change in `scripts/env.sh`.
- **noVNC laggy on mobile** — drop resolution by editing `SCREEN_GEOMETRY`
  in `scripts/env.sh` to `1024x768x24`. Or append
  `&quality=3&compression=6` to the noVNC URL.
- **Detector misses a CAPTCHA** — add the selector to
  `scripts/detect-captcha.js`; the watcher and the agent both read it.

## Security

- noVNC is password-protected (auto-generated at install, stored in
  `~/.hermes-takeover/vncpasswd.txt`).
- Default `BIND_ADDR=auto` listens on the Tailscale IP if Tailscale is up,
  else `127.0.0.1`. Nothing public unless you set `0.0.0.0` manually.
- Chrome profile lives at `~/.hermes-takeover/chrome-profile/`. Treat it like
  a personal browser — anything you log into persists.
- All notification credentials are env-only, never committed.

## Layout

```
captcha-takeover/
├── SKILL.md                        # agent-facing playbook
├── README.md                       # Bahasa Indonesia version
├── README.en.md                    # this file
├── install.sh                      # install all deps
├── start.sh / stop.sh / status.sh
├── doctor.sh                       # diagnose stack
├── info.sh                         # print noVNC + CDP URLs (also writes info.json)
├── watch-captcha.sh                # captcha watcher wrapper
├── new-instance.sh                 # spawn additional isolated instances
├── examples/                       # framework-specific integration code
│   ├── hermes.md
│   ├── playwright.md
│   ├── puppeteer.md
│   ├── selenium.md
│   └── manual-cdp.md
├── scripts/
│   ├── env.sh                      # runtime config (generated at install)
│   ├── detect-captcha.js           # drop-in CAPTCHA detector
│   ├── captcha-watcher.py          # polls Chrome, sends notifications
│   ├── telegram-notify.sh          # manual notify helper
│   └── watchdog.sh                 # auto-restart Chrome on crash
└── systemd/
    └── hermes-takeover.service     # auto-start unit file
```

## Limitations

- The watcher checks for known CAPTCHA vendors (see `detect-captcha.js`).
  Custom in-house challenges may need a new selector added.
- VNC over mobile cellular can be laggy for drag/scroll. Tap-to-click is
  fine.
- Chrome runs on Xvfb without GPU acceleration — heavy animations can be
  sluggish.
- Chrome session lives in `~/.hermes-takeover/chrome-profile/`. Deleting
  this wipes all logins.
- Single-user; no built-in access control beyond the VNC password and
  Tailscale tailnet.

## License

MIT — see [LICENSE](./LICENSE).
