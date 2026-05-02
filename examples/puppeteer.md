# Puppeteer integration

Connect Puppeteer to the running Chrome instead of launching your own.

```js
const puppeteer = require("puppeteer");
const fs = require("fs");
const path = require("path");
const os = require("os");

const INFO = JSON.parse(
  fs.readFileSync(path.join(os.homedir(), ".hermes-takeover", "info.json"))
);
const DETECT_JS = fs.readFileSync("scripts/detect-captcha.js", "utf8");

(async () => {
  const browser = await puppeteer.connect({ browserURL: INFO.cdp_http });
  const pages = await browser.pages();
  const page = pages[0] || (await browser.newPage());

  await page.goto("https://example.com/login");

  // Detection — call after every navigation / form submit.
  let sel = await page.evaluate(DETECT_JS);
  if (sel) {
    console.log(`CAPTCHA detected (${sel}). Open: ${INFO.novnc_url}`);
    while (await page.evaluate(DETECT_JS)) {
      await new Promise((r) => setTimeout(r, 5000));
    }
    console.log("CAPTCHA cleared, continuing.");
  }

  // ... rest of automation.
})();
```
