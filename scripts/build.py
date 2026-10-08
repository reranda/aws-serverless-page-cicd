"""Deterministic, dependency-free Lambda package."""
import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def build(commit, output=None):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("commit must be a full 40-character Git SHA")
    page = (ROOT / "content/index.html").read_bytes()
    release = {"commit": commit, "page_sha256": hashlib.sha256(page).hexdigest()}
    files = {"handler.py": (ROOT / "app/handler.py").read_bytes(), "index.html": page,
             "release.json": json.dumps(release, sort_keys=True).encode()}
    output = output or ROOT / "infrastructure/app/.build/page.zip"
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--commit", required=True)
    print(build(parser.parse_args().commit))

