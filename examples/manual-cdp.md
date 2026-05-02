# Manual CDP integration (any language)

If you're not using a high-level framework, you can speak Chrome DevTools
Protocol directly. This is what the bundled `scripts/captcha-watcher.py` does.

## Discover the WebSocket URL of a tab

```bash
curl -s http://127.0.0.1:9222/json | jq '.[] | select(.type=="page") | .webSocketDebuggerUrl'
```

## Open a new tab

```bash
curl -X PUT "http://127.0.0.1:9222/json/new?https://example.com/login"
```

## Run JS in a tab (Runtime.evaluate)

```python
import asyncio, json, websockets, requests

async def evaluate(ws_url: str, expr: str):
    async with websockets.connect(ws_url) as ws:
        await ws.send(json.dumps({
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {"expression": expr, "returnByValue": True},
        }))
        while True:
            msg = json.loads(await ws.recv())
            if msg.get("id") == 1:
                return msg["result"]["result"].get("value")

# Find the first page and run the captcha detector
DETECT_JS = open("scripts/detect-captcha.js").read()
tabs = requests.get("http://127.0.0.1:9222/json").json()
page = next(t for t in tabs if t["type"] == "page")
sel = asyncio.run(evaluate(page["webSocketDebuggerUrl"], DETECT_JS))
print("CAPTCHA?", sel)
```

## Useful endpoints

| URL | Description |
|-----|-------------|
| `GET  http://127.0.0.1:9222/json/version` | Browser version + WS browser-level URL |
| `GET  http://127.0.0.1:9222/json` | List of tabs (each has `webSocketDebuggerUrl`) |
| `PUT  http://127.0.0.1:9222/json/new?<url>` | Open a new tab on `<url>` |
| `GET  http://127.0.0.1:9222/json/close/<id>` | Close a tab |
| `GET  http://127.0.0.1:9222/json/activate/<id>` | Bring a tab to front |

CDP method reference: <https://chromedevtools.github.io/devtools-protocol/>.
