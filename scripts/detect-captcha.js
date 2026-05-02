// detect-captcha.js — drop into your CDP Runtime.evaluate() / page.evaluate() call.
// Returns the matched selector string if a CAPTCHA is on the page, or null.
//
// Covers: reCAPTCHA v2/v3, hCaptcha, Cloudflare Turnstile, Cloudflare interstitial
// challenge, generic captcha/challenge iframes (e.g. Arkose, GeeTest, Lemin).
//
// Usage examples:
//   Playwright:  await page.evaluate(<contents of this file>)
//   Puppeteer:   await page.evaluate(<contents of this file>)
//   Selenium:    driver.execute_script("return (" + open(...).read() + ")()")
//   CDP raw:     {"method":"Runtime.evaluate","params":{"expression":"<this>", "returnByValue":true}}

(() => {
  const sels = [
    'iframe[src*="recaptcha"]',
    'iframe[src*="hcaptcha"]',
    'iframe[src*="turnstile"]',
    'iframe[src*="arkoselabs"]',
    'iframe[src*="funcaptcha"]',
    'iframe[src*="geetest"]',
    'iframe[src*="captcha"]',
    'div[class*="cf-turnstile"]',
    'div.g-recaptcha',
    'div.h-captcha',
    'div#cf-challenge-stage',
    'div#challenge-stage',
    'form#challenge-form',
    'iframe[title*="captcha" i]',
    'iframe[title*="challenge" i]',
    'iframe[title*="verifying" i]',
  ];
  for (const s of sels) {
    if (document.querySelector(s)) return s;
  }
  return null;
})();
