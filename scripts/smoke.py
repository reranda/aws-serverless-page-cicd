"""Verify the deployed content and full release SHA, with bounded retries."""
import argparse
import hashlib
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def verify(url, commit):
    with urllib.request.urlopen(url + "/health", timeout=10) as response:
        health = json.load(response)
    with urllib.request.urlopen(url + "/", timeout=10) as response:
        page = response.read()
        assert response.headers.get_content_type() == "text/html"
        assert response.headers["X-Release-Sha"] == commit
        assert response.headers["X-Content-Type-Options"] == "nosniff"
    expected = (ROOT / "content/index.html").read_bytes()
    assert health["status"] == "ok" and health["commit"] == commit
    assert health["page_sha256"] == hashlib.sha256(expected).hexdigest()
    assert page == expected, "The deployed page differs from the reviewed Git content"
    try:
        urllib.request.urlopen(url + "/missing", timeout=10)
        raise AssertionError("An unknown route should return 404")
    except urllib.error.HTTPError as error:
        assert error.code == 404


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    for attempt in range(6):
        try:
            verify(args.url.rstrip("/"), args.commit)
            print(f"Verified release {args.commit}: {args.url}")
            break
        except (AssertionError, OSError, ValueError, KeyError):
            if attempt == 5:
                raise
            time.sleep(5)

