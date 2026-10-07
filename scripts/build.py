"""Build a deterministic, allowlisted ZIP for the Python Lambda runtime."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def build(commit, output, source=ROOT):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Release commit must be a full lowercase Git SHA")
    page = (source / "content/index.html").read_bytes()
    page.decode("utf-8")
    if not page or len(page) > 256 * 1024:
        raise ValueError("The page must be between 1 byte and 256 KiB")
    release = {"commit": commit, "content_sha256": hashlib.sha256(page).hexdigest()}
    manifest = (json.dumps(release, sort_keys=True) + "\n").encode()
    files = {
        "handler.py": (source / "app/handler.py").read_bytes(),
        "content/index.html": page,
        "release.json": manifest,
    }
    output.mkdir(parents=True, exist_ok=True)
    package = output / "lambda.zip"
    with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(files.items()):
            entry = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    (output / "release.json").write_bytes(manifest)
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    (output / "lambda.zip.sha256").write_text(digest + "\n", encoding="utf-8")
    return package


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "build")
    args = parser.parse_args()
    build(args.commit, args.output)
    print("Created deterministic Lambda package and release manifest")
