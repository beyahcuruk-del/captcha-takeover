---
name: captcha-takeover
description: |
  Lets a human user manually solve CAPTCHAs (reCAPTCHA, hCaptcha, Cloudflare
  Turnstile, etc.) when an autonomous browser agent gets blocked by one. Use
  this skill whenever browser automation hits a CAPTCHA challenge that cannot
  be solved programmatically. Provides a private noVNC web URL the user can
  open from any device (phone, laptop) to view the agent's browser live and
  click through the CAPTCHA. Works framework-agnostic via Chrome DevTools
  Protocol (CDP) — connects to Hermes, Playwright, Puppeteer, Selenium, or any
  tool that speaks CDP.
when_to_use:
  - Browser navigation stops at "I'm not a robot" / "Verify you are human" / image puzzle.
  - Page returns Cloudflare interstitial ("Checking your browser…", "Just a moment…").
  - Login flow requires SMS or 2FA code on a screen the user can see.
  - Any time the agent cannot proceed because of a human-verification step.
license: MIT
---

# captcha-takeover

A self-contained "human-takeover" infrastructure for browser-automation agents.
Run it on the same machine as your agent (Linux/Ubuntu VPS recommended); when a
CAPTCHA blocks you, send the user a single URL and they solve it from their
phone in seconds.

## How it works

```
+------------------+      CDP ws://127.0.0.1:9222     +-------------------+
|  YOUR AGENT      | <------------------------------> | Chrome (headed,   |
|  (Hermes /       |                                  |  on Xvfb :1)      |
|   Playwright /   |                                  +-------------------+
|   Puppeteer /    |                                          |
|   Selenium /     |                                          | x11vnc capture
|   any CDP tool)  |                                          v
+------------------+                                  +-------------------+
                                                      | VNC server :5901  |
                                                      +-------------------+
                                                                |
                                                                | websockify
                                                                v
                                                      +-------------------+
                                                      | noVNC web :6080   |
                                                      +-------------------+
                                                                |
                                                          Tailscale (private)
                                                                |
                                                                v
                                                          User's phone
```

Your agent talks to Chrome over CDP exactly the same way it always does. The
only difference: Chrome runs on a virtual X display that's also being streamed
to the user via noVNC over Tailscale.

## Install (one-time per machine, ~3 minutes)

```bash
git clone https://github.com/beyahcuruk-del/captcha-takeover.git
cd captcha-takeover
chmod +x *.sh scripts/*.sh
./install.sh                  # installs Xvfb, Chrome, x11vnc, noVNC, Tailscale, Python deps
sudo tailscale up             # one-time login on this machine
# Install Tailscale app on phone, sign in with the same account.
```

## Start (per session)

```bash
./start.sh
```

Output prints the **noVNC URL with embedded password** + the **CDP URL** the
agent should connect to.

## Stop / status / diagnose

```bash
./stop.sh
./status.sh
./doctor.sh         # diagnoses dependency / port / health issues
./info.sh           # re-prints connection info (URL + Hermes command)
```

## Agent integration (read this carefully)

**Step 1 — Connect to Chrome via CDP.**

Always connect to `ws://127.0.0.1:9222` (or the host where you ran `start.sh`).
Do NOT launch your own Chrome instance — connect to the one this skill manages,
otherwise the user's noVNC view will be empty.

| Framework | Connect call |
|-----------|--------------|
| Hermes (CLI) | `/browser connect ws://127.0.0.1:9222` |
| Playwright | `chromium.connect_over_cdp("http://127.0.0.1:9222")` |
| Puppeteer | `puppeteer.connect({ browserURL: "http://127.0.0.1:9222" })` |
| Selenium 4 | `ChromeOptions().debugger_address = "127.0.0.1:9222"` |
| Plain CDP | `ws://127.0.0.1:9222/devtools/browser/<id>` |

See `examples/` for full code per framework.

**Step 2 — Detect CAPTCHA.**

Load and run the bundled detector inside any page after navigation:

```js
// Read scripts/detect-captcha.js as a string, then in your framework:
//   Playwright: await page.evaluate(detectJsString)
//   Puppeteer:  await page.evaluate(detectJsString)
//   Selenium:   driver.execute_script("return " + detectJsString)
//   Raw CDP:    {"method":"Runtime.evaluate", "params":{"expression": detectJsString, "returnByValue": true}}
```

It returns `"<vendor>:<selector>"` when a CAPTCHA is on screen, `null`
otherwise. Vendors covered: **reCAPTCHA, hCaptcha, Cloudflare Turnstile +
interstitial, Arkose / FunCaptcha, GeeTest, DataDome, PerimeterX / HUMAN,
Akamai Bot Manager, Imperva (Incapsula), Kasada, AWS WAF, Lemin**, plus a
generic iframe fallback and a text-heuristic for "Verify you are human" /
"Just a moment…" pages. Add new selectors to the bottom of the file when you
find a vendor it misses.

The exact same detector runs in `scripts/captcha-watcher.py` if you want
background polling instead.

**Step 3 — Hand control to the user.**

When CAPTCHA is detected, your agent should:

1. **Pause** all automation.
2. **Get the takeover URL** by reading the file the skill writes after each
   `start.sh`:
   ```bash
   ./info.sh --json
   ```
   or read `~/.hermes-takeover/info.json` (keys: `novnc_url`, `vnc_password`,
   `cdp_url`, `tailscale_ip`).
3. **Tell the user** with a message like:
   ```
   I hit a CAPTCHA on <PAGE_URL>. Open this from your phone and solve it for
   me, I'll continue once you're done:

       <novnc_url>
   ```
4. **Wait for the CAPTCHA to disappear** before resuming. Poll the same
   detection JS every 5–10 s until it returns null. Or wait for an explicit
   "done" signal from the user.

**Step 4 — Resume.**

Once detection returns null, continue the original task. The session/cookies
the user just earned are preserved in the same Chrome instance, so the agent
inherits them automatically.

## Notification options (optional)

If you want the user pinged when a CAPTCHA shows up (so they don't have to
watch Chrome), enable the watcher:

```bash
./watch-captcha.sh start    # background process, polls Chrome every 5 s
```

It writes every detection to `~/.hermes-takeover/logs/captcha-events.log` and
fans out to whichever channels are configured in `scripts/env.sh`:

| Channel | Variables to set |
|---------|------------------|
| Telegram | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` |
| ntfy.sh | `NTFY_TOPIC` (and optionally `NTFY_SERVER`, `NTFY_TOKEN`) |
| Discord | `DISCORD_WEBHOOK_URL` |
| Slack | `SLACK_WEBHOOK_URL` |
| Email (SMTP) | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`, `SMTP_TO` |

Multiple channels can be set at once; all of them get the same notification.
If none are set, events still go to the local log file.

## Limitations

- This skill solves the *delivery* problem, not the CAPTCHA itself. The user
  has to actually solve it.
- Chrome runs headed under Xvfb — no GPU, so heavily-animated sites may feel
  slow over mobile networks.
- Default bind is `auto` (Tailscale IP if up, else 127.0.0.1). Avoid
  `0.0.0.0` unless you need public exposure (use Cloudflare Tunnel + Access
  for that — out of scope for this skill).
- One Chrome instance per install dir. Use `./new-instance.sh <name> <port-offset>`
  to spawn additional isolated instances (each gets its own `RUN_DIR`,
  Chrome profile, X display, and port set).
- A built-in watchdog auto-restarts Chrome if it crashes mid-session.
  Disable with `START_WATCHDOG=0 ./start.sh`.

## See also

- `README.md` — human-facing setup walkthrough (Bahasa Indonesia).
- `README.en.md` — same walkthrough in English.
- `examples/` — copy-paste integration code for each framework.
