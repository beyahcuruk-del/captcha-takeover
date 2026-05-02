# Hermes Captcha Takeover Stack

Setup biar lu bisa **takeover captcha dari HP** padahal Hermes Agent jalan di
VPS Ubuntu. Pas captcha muncul, Hermes biasanya stuck — lu tinggal buka URL di
Chrome HP, klik captcha, agent lanjut.

## Quick Test (5 menit di VPS)

```bash
# 1. Upload + unzip
unzip hermes-takeover.zip && cd hermes-takeover

# 2. Install semua deps (Xvfb, Chrome, Tailscale, dll)
chmod +x *.sh scripts/*.sh
./install.sh

# 3. Login Tailscale (sekali aja, buka URL yang muncul di HP/laptop)
sudo tailscale up
# Install app "Tailscale" di HP, login akun Google yg sama, aktifin

# 4. Start stack — output langsung kasih URL noVNC + Hermes connect command
./start.sh

# 5. Buka URL noVNC dari output di atas, di Chrome HP

# 6. Connect Hermes ke Chrome (di terminal Hermes):
hermes chat
# di prompt:  /browser connect ws://127.0.0.1:9222
```

Selesai. Pas captcha muncul → buka URL noVNC di HP → klik captcha pake jari → agent lanjut.

**Helper scripts:**
- `./doctor.sh` — diagnose dependency / port / health issue
- `./hermes-info.sh` — re-print URL noVNC + command Hermes
- `./status.sh` — cek semua komponen UP/OFF
- `./stop.sh` / `./start.sh` — restart cycle

## Cara kerja

```
Hermes Agent (di VPS)
   ↓ /browser connect ws://localhost:9222
Chrome (--remote-debugging-port=9222)
   ↓ render ke
Xvfb display :1 (virtual screen)
   ↓ x11vnc
VNC server (localhost:5901)
   ↓ websockify + noVNC
HTTP server (port 6080) — bisa diakses via browser HP
   ↓
Tailscale (VPN privat antar device)
   ↓
Lu di HP buka URL → liat layar VPS → klik captcha
```

Bonus: ada `captcha-watcher.py` yang polling Chrome dan kirim notif Telegram
pas captcha muncul, lengkap dengan screenshot dan link langsung ke VNC.

## Prasyarat

- VPS Ubuntu 20.04 / 22.04 / 24.04 dengan akses sudo
- HP punya app **Tailscale** (gratis dari Play Store / App Store)
- (Opsional) Bot Telegram + chat ID kalau mau notif

## Install (di VPS)

```bash
# 1. Copy folder ini ke VPS
scp -r hermes-takeover user@vps:/home/user/

# 2. SSH ke VPS, cd ke folder
ssh user@vps
cd ~/hermes-takeover

# 3. Run installer
chmod +x install.sh start.sh stop.sh status.sh watch-captcha.sh
./install.sh
```

Installer akan:
- Install Xvfb, fluxbox, x11vnc, websockify, noVNC, Google Chrome, Tailscale, Python deps
- Bikin folder `~/.hermes-takeover/` (logs, PID, Chrome profile, password VNC)
- Generate password VNC random, simpan di `~/.hermes-takeover/vncpasswd.txt`
- Bikin `scripts/env.sh` default

## Setup Tailscale (sekali aja)

```bash
sudo tailscale up
```

Tailscale akan kasih URL — buka di Chrome HP/laptop, login Google. VPS lu
sekarang ada di "tailnet" lu, bisa diakses dari HP via IP `100.x.x.x`.

```bash
tailscale ip -4   # cek IP VPS lu
```

Di HP, **install Tailscale app, login akun Google yang sama**, dan aktifkan.
Sekarang HP & VPS bisa saling kontak via IP Tailscale (100.x.x.x).

## Start stack

```bash
./start.sh
```

Output akan kasih tau URL VNC dan password. Contoh:

```
noVNC URL: http://100.64.5.12:6080/vnc.html?autoconnect=1&resize=remote
VNC password: AbCd1234XyZ
```

Buka URL itu di **Chrome HP**. Akan muncul layar virtual VPS lu — kalau Chrome
belum jalan apa-apa, akan blank/abu-abu. Begitu Hermes navigate ke website,
lu bakal liat website itu di HP.

## Connect Hermes ke Chrome

Di terminal VPS:

```bash
hermes chat
```

Lalu di prompt Hermes:

```
/browser connect ws://127.0.0.1:9222
```

Hermes akan attach ke Chrome yang udah jalan. Sekarang setiap perintah browser
yang dia lakuin (navigate, click, dll) akan render di Chrome itu — dan **lu bisa
liat live di HP**.

> **Penting:** Kalau Hermes jalan di VPS yang sama, ws://127.0.0.1:9222 work.
> Kalau Hermes jalan di mesin lain (laptop lu, dll), ganti ke `ws://<TAILSCALE_IP>:9222`
> dan ubah `BIND_ADDR` di `scripts/env.sh` jadi IP Tailscale, lalu restart.

## Saat captcha muncul

1. Hermes biasanya stuck atau retry-retry karena gak bisa solve captcha
2. Lu buka URL VNC di Chrome HP (yang udah lu bookmark)
3. Pakai jari, klik checkbox / solve captcha kayak biasa
4. Begitu captcha kelar, Hermes auto lanjut karena dia connect ke Chrome yang sama

## (Opsional) Notif Telegram saat captcha muncul

### 1. Bikin bot

- Chat ke `@BotFather` di Telegram, kirim `/newbot`, ikuti instruksi
- Lu dapet `Bot Token` (string panjang kayak `1234567890:ABCdef...`)

### 2. Dapatin chat ID

- Chat ke bot lu, kirim apa aja (misal `/start`)
- Buka di browser: `https://api.telegram.org/bot<TOKEN>/getUpdates`
- Cari `"chat":{"id":<ANGKA>}` — itu chat ID lu

### 3. Isi di env.sh

```bash
nano scripts/env.sh
```

Edit:

```bash
export TELEGRAM_BOT_TOKEN="1234567890:ABCdef..."
export TELEGRAM_CHAT_ID="123456789"
```

### 4. Test

```bash
./scripts/telegram-notify.sh "test notif"
```

HP lu harusnya dapet ping dari bot.

### 5. Jalanin watcher

```bash
./watch-captcha.sh start
./watch-captcha.sh logs    # tail log
./watch-captcha.sh stop
```

Watcher akan polling Chrome tiap 5 detik, kalau detect captcha (reCAPTCHA,
hCaptcha, Cloudflare Turnstile) langsung kirim notif + screenshot + link VNC ke
Telegram lu. Cooldown 2 menit biar gak spam.

## Status / Stop / Restart

```bash
./status.sh           # cek semua komponen
./stop.sh             # stop semua
./start.sh            # start lagi
```

## Auto-start saat reboot (opsional)

```bash
# Edit unit file, ganti USER ke username VPS lu (e.g. ubuntu, root)
sed -i "s/USER/$(whoami)/g" systemd/hermes-takeover.service

# Install
sudo cp systemd/hermes-takeover.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-takeover.service

# Cek
sudo systemctl status hermes-takeover.service
```

## Troubleshooting

### Gak bisa konek dari HP

- Pastikan Tailscale aktif di HP (icon centang di app Tailscale)
- Pastikan `tailscale status` di VPS nampilin HP lu sebagai online
- Coba akses dari laptop dulu (laptop juga harus install Tailscale)
- Kalau masih gak bisa, ganti `BIND_ADDR` di `scripts/env.sh` ke IP Tailscale
  VPS (`tailscale ip -4`), lalu `./stop.sh && ./start.sh`

### Chrome gak start / "Failed to launch"

- Cek log: `cat ~/.hermes-takeover/logs/chrome.log`
- Sering karena `--no-sandbox` ditolak. Sudah include di flags default.
- Kalau VPS punya RAM kecil (<1GB), Chrome bisa OOM. Coba tambah swap atau
  upgrade VPS.

### "X11 connection rejected" / Display gak bisa diakses

- Restart full: `./stop.sh && rm -f /tmp/.X1-lock /tmp/.X11-unix/X1; ./start.sh`

### noVNC nampilin layar tapi gak bisa klik / kursor laggy

- Wajar di koneksi mobile lambat. Coba turunin resolusi: edit `SCREEN_GEOMETRY`
  di `scripts/env.sh` jadi `"1024x768x24"`, restart.
- Atau buka noVNC URL dengan tambahan `&quality=3&compression=6` (lebih cepet,
  agak burem)

### Hermes gak detect Chrome

- Pastikan `curl http://127.0.0.1:9222/json/version` di VPS return JSON
- Kalau Hermes di mesin lain, gunakan IP Tailscale VPS dan pastikan
  `BIND_ADDR=0.0.0.0` (atau IP Tailscale spesifik) di env.sh — bukan `127.0.0.1`

### Watcher Telegram gak detect captcha

- Captcha-nya mungkin di iframe yang gak match selector default. Edit
  `DETECT_JS` di `scripts/captcha-watcher.py` tambah selector custom.
- Atau kirim notif manual: `./scripts/telegram-notify.sh "captcha lur"`

## Keamanan

- noVNC pake password (random, di-generate saat install). Disimpan di
  `~/.hermes-takeover/vncpasswd.txt` — **jangan share**.
- Default bind ke `127.0.0.1`, jadi gak ada port public exposed. Tailscale
  yang bridge HP ke VPS via VPN privat.
- Chrome profile di `~/.hermes-takeover/chrome-profile/` — kalau lu login akun
  apa pun di sini, cookie & session akan persist. Treat ini kayak browser
  pribadi.
- Telegram bot token & chat ID disimpan di `scripts/env.sh` — file mode 600 by
  default, tapi pastiin folder `hermes-takeover/` gak ke-commit ke git public.

## File layout

```
hermes-takeover/
├── install.sh                      # install semua dependency
├── start.sh                        # start stack
├── stop.sh                         # stop stack
├── status.sh                       # cek status
├── watch-captcha.sh                # wrapper watcher
├── README.md                       # ini
├── scripts/
│   ├── env.sh                      # konfigurasi (di-generate saat install)
│   ├── telegram-notify.sh          # helper kirim notif manual
│   └── captcha-watcher.py          # auto-detect captcha
└── systemd/
    └── hermes-takeover.service     # unit file untuk auto-start
```

## Limitations

- Watcher cuma detect captcha jenis umum (reCAPTCHA v2/v3, hCaptcha, Cloudflare
  Turnstile). Captcha custom site mungkin gak ke-detect.
- VNC over mobile cellular bisa laggy untuk drag/scroll. Tap & klik harusnya OK.
- Chrome di Xvfb VPS gak punya GPU acceleration — animasi heavy site bisa berat.
- Cookie/login Chrome ada di `~/.hermes-takeover/chrome-profile/`, kalau lu
  hapus folder itu, semua login hilang.
