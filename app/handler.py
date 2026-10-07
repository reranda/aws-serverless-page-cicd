"""Serve the HTML bundled with a published Lambda release; no network or SDK."""

import hashlib
import json
import logging
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PAGE = (ROOT / "content" / "index.html").read_bytes()
RELEASE = json.loads((ROOT / "release.json").read_text(encoding="utf-8"))
PAGE_SHA256 = hashlib.sha256(PAGE).hexdigest()
if RELEASE["content_sha256"] != PAGE_SHA256:
    raise RuntimeError("Packaged content does not match the release manifest")

LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(logging.INFO)
HEADERS = {
    "Cache-Control": "no-cache, max-age=0, must-revalidate",
    "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    "Referrer-Policy": "no-referrer",
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
}


def handler(event, context):
    """API Gateway REST API Lambda proxy response. Routes never select files."""
    method = event.get("httpMethod", "")
    path = event.get("path", "")
    headers = {**HEADERS, "Content-Type": "text/plain; charset=utf-8"}
    status, body = 404, "Not found\n"
    if method not in {"GET", "HEAD"}:
        status, body = 405, "Method not allowed\n"
        headers["Allow"] = "GET, HEAD"
    elif path in {"/", "/index.html"}:
        status, body = 200, PAGE.decode("utf-8")
        headers["Content-Type"] = "text/html; charset=utf-8"
        headers["ETag"] = f'"{PAGE_SHA256}"'
        request_headers = {str(k).lower(): v for k, v in (event.get("headers") or {}).items()}
        if request_headers.get("if-none-match") == headers["ETag"]:
            status, body = 304, ""
    elif path == "/health":
        status = 200
        headers["Content-Type"] = "application/json; charset=utf-8"
        headers["Cache-Control"] = "no-store"
        body = json.dumps({"status": "ok", **RELEASE}, sort_keys=True)
    if method == "HEAD":
        body = ""
    # Do not record request bodies, headers, IP addresses, or arbitrary paths.
    LOGGER.info(json.dumps({
        "event": "request", "status": status,
        "route": path if path in {"/", "/index.html", "/health"} else "unmatched",
        "request_id": getattr(context, "aws_request_id", "local"),
    }, sort_keys=True))
    return {"statusCode": status, "headers": headers, "body": body, "isBase64Encoded": False}
