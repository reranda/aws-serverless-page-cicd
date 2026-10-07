"""Verify the deployed API's release identity, page bytes and HTTP behavior."""

import argparse
import hashlib
import json
from pathlib import Path
import time
import urllib.error
import urllib.parse
import urllib.request


def request(url, method="GET", headers=None):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, method=method, headers=headers or {}), timeout=15) as response:
            return response.status, dict(response.headers), response.read()
    except urllib.error.HTTPError as response:
        return response.code, dict(response.headers), response.read()


def verify(url, release):
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("Smoke test requires a clean HTTPS API base URL")
    url = url.rstrip("/")
    status, headers, body = request(url + "/")
    headers = {key.lower(): value for key, value in headers.items()}
    assert status == 200, f"Page returned {status}"
    assert "text/html" in headers.get("content-type", ""), "HTML content type missing"
    assert hashlib.sha256(body).hexdigest() == release["content_sha256"], "Served page digest mismatch"
    assert headers.get("x-content-type-options") == "nosniff", "nosniff header missing"
    assert "frame-ancestors 'none'" in headers.get("content-security-policy", ""), "CSP missing"
    assert headers.get("x-frame-options") == "DENY", "Frame protection missing"
    status, _, body = request(url + "/health")
    health = json.loads(body)
    assert status == 200 and health.get("status") == "ok", "Health check failed"
    assert health.get("commit") == release["commit"], "Running commit mismatch"
    assert health.get("content_sha256") == release["content_sha256"], "Running content digest mismatch"
    assert request(url + "/", method="HEAD")[0::2] == (200, b""), "HEAD behavior failed"
    assert request(url + "/missing")[0] == 404, "Missing route should return 404"
    assert request(url + "/", method="POST")[0] == 405, "Writes must be rejected"
    assert request(url + "/", headers={"If-None-Match": headers["etag"]})[0] == 304, "ETag behavior failed"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--release", type=Path, default=Path("build/release.json"))
    args = parser.parse_args()
    release = json.loads(args.release.read_text(encoding="utf-8"))
    for attempt in range(6):
        try:
            verify(args.url, release)
            break
        except (AssertionError, urllib.error.URLError, json.JSONDecodeError):
            if attempt == 5:
                raise
            time.sleep(5)
    print(f"Verified release {release['commit']} through the API")
