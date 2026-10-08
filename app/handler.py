"""Serve only the HTML packaged with this release. No network or GitHub token needed."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PAGE = (ROOT / "index.html").read_text(encoding="utf-8")
RELEASE = json.loads((ROOT / "release.json").read_text(encoding="utf-8"))
STYLE = PAGE.split("<style>", 1)[1].split("</style>", 1)[0] if "<style>" in PAGE else ""
# Inline CSS is allowed by its hash; scripts and external resources are forbidden.
import base64
STYLE_HASH = base64.b64encode(hashlib.sha256(STYLE.encode()).digest()).decode()
HEADERS = {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Strict-Transport-Security": "max-age=31536000",
    "Content-Security-Policy": (
        "default-src 'none'; style-src 'sha256-" + STYLE_HASH + "'; "
        "base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
    ),
    "X-Release-Sha": RELEASE["commit"],
}


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path = event.get("rawPath", "/")
    if method not in ("GET", "HEAD"):
        return {"statusCode": 405, "headers": {**HEADERS, "Allow": "GET, HEAD"}, "body": "Method not allowed"}
    if path == "/health":
        return {"statusCode": 200, "headers": {**HEADERS, "Content-Type": "application/json"},
                "body": "" if method == "HEAD" else json.dumps({"status": "ok", **RELEASE})}
    if path not in ("/", "/index.html"):
        return {"statusCode": 404, "headers": HEADERS, "body": "Not found"}
    return {"statusCode": 200, "headers": HEADERS, "body": "" if method == "HEAD" else PAGE,
            "isBase64Encoded": False}

