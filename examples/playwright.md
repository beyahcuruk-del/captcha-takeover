# Playwright integration (Python + Node)

The captcha-takeover stack runs Chrome on `127.0.0.1:9222`. Connect to it from
Playwright instead of launching your own browser.

## Python

```python
import asyncio, json, time
from pathlib import Path
from playwright.async_api import async_playwright

INFO = Path.home() / ".hermes-takeover" / "info.json"
DETECT_JS = Path("scripts/detect-captcha.js").read_text()

async def main():
    info = json.loads(INFO.read_text())
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(info["cdp_http"])
        context = browser.contexts[0] if browser.contexts else await browser.new_context()
        page = context.pages[0] if context.pages else await context.new_page()

        await page.goto("https://example.com/login")

        # Detection loop — call after every navigation / form submit.
        sel = await page.evaluate(DETECT_JS)
        if sel:
            print(f"CAPTCHA detected ({sel}). Ask user to solve at:\n  {info['novnc_url']}")
            # Wait until the user solves it.
            while await page.evaluate(DETECT_JS):
                await asyncio.sleep(5)
            print("CAPTCHA cleared, continuing.")

        # ... rest of automation runs as normal.

asyncio.run(main())
```

## Node

```js
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");
const os = require("os");

const INFO = JSON.parse(
  fs.readFileSync(path.join(os.homedir(), ".hermes-takeover", "info.json"))
);
const DETECT_JS = fs.readFileSync("scripts/detect-captcha.js", "utf8");

(async () => {
  const browser = await chromium.connectOverCDP(INFO.cdp_http);
  const context = browser.contexts()[0] || (await browser.newContext());
  const page = context.pages()[0] || (await context.newPage());

  await page.goto("https://example.com/login");

  let sel = await page.evaluate(DETECT_JS);
  if (sel) {
    console.log(`CAPTCHA detected (${sel}). Open ${INFO.novnc_url} from your phone.`);
    while (await page.evaluate(DETECT_JS)) {
      await new Promise((r) => setTimeout(r, 5000));
    }
    console.log("CAPTCHA cleared, continuing.");
  }

  // ... rest of automation.
})();
```
