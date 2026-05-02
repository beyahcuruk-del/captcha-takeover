# Selenium integration (Python)

Selenium 4 supports attaching to an existing Chrome via the `debuggerAddress`
option.

```python
import json, time
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.chrome.options import Options

INFO = json.loads((Path.home() / ".hermes-takeover" / "info.json").read_text())
DETECT_JS = "return " + Path("scripts/detect-captcha.js").read_text()

opts = Options()
opts.add_experimental_option("debuggerAddress", INFO["cdp_addr"])  # e.g. "127.0.0.1:9222"
driver = webdriver.Chrome(options=opts)

driver.get("https://example.com/login")

sel = driver.execute_script(DETECT_JS)
if sel:
    print(f"CAPTCHA detected ({sel}). Open from phone: {INFO['novnc_url']}")
    while driver.execute_script(DETECT_JS):
        time.sleep(5)
    print("CAPTCHA cleared, continuing.")

# ... rest of automation. Don't call driver.quit() — that would close the
# managed Chrome. Just stop the script.
```

**Important:** Do NOT call `driver.quit()` at the end. That would close the
managed Chrome instance and break subsequent runs. Just let the script exit.
