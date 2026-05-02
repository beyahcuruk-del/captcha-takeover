// detect-captcha.js — drop into your CDP Runtime.evaluate() / page.evaluate() call.
// Returns a string identifying the matched challenge if a CAPTCHA / bot-check is on
// the page, or null. Format: "<vendor>:<selector>" so callers can route by vendor.
//
// Covers (as of v0.2.0):
//   reCAPTCHA v2/v3, hCaptcha, Cloudflare Turnstile, Cloudflare interstitial,
//   Arkose Labs / FunCaptcha, GeeTest, DataDome, PerimeterX / HUMAN, Akamai
//   Bot Manager, Imperva (Incapsula), Kasada, AWS WAF, generic
//   captcha/challenge iframes, Google "unusual traffic" page.
//
// Usage examples:
//   Playwright:  await page.evaluate(<contents of this file>)
//   Puppeteer:   await page.evaluate(<contents of this file>)
//   Selenium:    driver.execute_script("return (" + open(...).read() + ")()")
//   CDP raw:     {"method":"Runtime.evaluate","params":{"expression":"<this>", "returnByValue":true}}

(() => {
  // [vendor, selector] pairs. First match wins. Order matters: more-specific
  // vendor selectors first, generic fallbacks last.
  const probes = [
    // Cloudflare
    ["cloudflare-turnstile",  'div[class*="cf-turnstile"]'],
    ["cloudflare-turnstile",  'iframe[src*="challenges.cloudflare.com"]'],
    ["cloudflare-challenge",  '#challenge-form'],
    ["cloudflare-challenge",  '#cf-challenge-stage'],
    ["cloudflare-challenge",  '#challenge-stage'],
    ["cloudflare-challenge",  'iframe[src*="cdn-cgi/challenge-platform"]'],

    // Google reCAPTCHA
    ["recaptcha",             'iframe[src*="recaptcha"]'],
    ["recaptcha",             'div.g-recaptcha'],
    ["recaptcha",             'iframe[src*="google.com/recaptcha"]'],

    // hCaptcha
    ["hcaptcha",              'iframe[src*="hcaptcha"]'],
    ["hcaptcha",              'div.h-captcha'],
    ["hcaptcha",              'iframe[src*="newassets.hcaptcha.com"]'],

    // Arkose Labs (FunCaptcha — Twitter/X, LinkedIn, etc.)
    ["arkose",                'iframe[src*="arkoselabs"]'],
    ["arkose",                'iframe[src*="funcaptcha"]'],
    ["arkose",                'div#funcaptcha'],
    ["arkose",                'div[id*="arkose"]'],

    // GeeTest
    ["geetest",               'iframe[src*="geetest"]'],
    ["geetest",               'div.geetest_holder'],
    ["geetest",               'div.geetest_panel'],

    // DataDome
    ["datadome",              'iframe[src*="captcha-delivery.com"]'],
    ["datadome",              'div#datadome'],
    ["datadome",              'iframe[id*="datadome"]'],

    // PerimeterX / HUMAN
    ["perimeterx",            'div#px-captcha'],
    ["perimeterx",            'iframe[src*="captcha.px-cdn.net"]'],
    ["perimeterx",            'iframe[src*="perimeterx"]'],

    // Akamai Bot Manager
    ["akamai",                'iframe[src*="akam"]'],
    ["akamai",                'div[data-akamai-mpulse]'],
    ["akamai",                'div#akami-challenge'],

    // Imperva / Incapsula
    ["imperva",               'iframe[src*="incapsula"]'],
    ["imperva",               'iframe[id*="imperva"]'],
    ["imperva",               'div#imperva-captcha'],

    // Kasada
    ["kasada",                'iframe[src*="kasadacdn"]'],
    ["kasada",                'script[src*="kasadacdn"]'],

    // AWS WAF Captcha
    ["aws-waf",               'iframe[src*="awswaf.com"]'],
    ["aws-waf",               'div#aws-waf-captcha'],
    ["aws-waf",               'div[class*="aws-waf"]'],

    // Lemin
    ["lemin",                 'iframe[src*="lemin"]'],
    ["lemin",                 'div#lemin-cropped-captcha'],

    // Google "unusual traffic" / sorry page
    ["google-sorry",          'form[action*="/sorry"]'],
    ["google-sorry",          'div#captcha-form'],

    // Generic captcha / challenge iframes (last-resort fallback)
    ["generic-iframe",        'iframe[src*="captcha"]'],
    ["generic-iframe",        'iframe[title*="captcha" i]'],
    ["generic-iframe",        'iframe[title*="challenge" i]'],
    ["generic-iframe",        'iframe[title*="verifying" i]'],
    ["generic-iframe",        'iframe[title*="verify you are human" i]'],
  ];

  for (const [vendor, sel] of probes) {
    if (document.querySelector(sel)) {
      return vendor + ":" + sel;
    }
  }

  // Generic text-based heuristic (last fallback) — matches phrases that almost
  // always indicate a human-verification gate. Kept narrow on purpose.
  const bodyText = (document.body && document.body.innerText) || "";
  const phrases = [
    "Verify you are human",
    "Please verify you are a human",
    "Checking your browser before accessing",
    "Just a moment...",
    "Please complete the security check",
    "Our systems have detected unusual traffic",
    "Are you a robot?",
  ];
  for (const p of phrases) {
    if (bodyText.includes(p)) return "text-heuristic:\"" + p + "\"";
  }

  return null;
})();
