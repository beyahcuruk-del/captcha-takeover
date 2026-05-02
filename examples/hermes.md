# Hermes Agent integration

[Hermes](https://hermes-agent.nousresearch.com/) supports CDP via the `/browser`
command.

## One-time setup on the VPS

```bash
git clone https://github.com/beyahcuruk-del/captcha-takeover.git
cd captcha-takeover
chmod +x *.sh scripts/*.sh
./install.sh
sudo tailscale up        # log in once; install Tailscale on your phone too
```

## Each session

```bash
./start.sh               # prints noVNC URL + connect command
hermes chat
```

In the Hermes prompt:

```
/browser connect ws://127.0.0.1:9222
```

Then give Hermes a task as usual. When it hits a CAPTCHA it usually stops and
asks for help — open the noVNC URL on your phone, click through the CAPTCHA,
then tell Hermes to continue.

## Optional: auto-detect + Telegram ping

```bash
# Edit Telegram creds (optional)
$EDITOR scripts/env.sh   # set TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID

# Start the watcher (background)
./watch-captcha.sh start
```

Now whenever Hermes navigates into a CAPTCHA, you get a Telegram ping with
screenshot + the takeover URL — no need to babysit.
