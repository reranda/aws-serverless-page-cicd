"""Envelope-encrypt a saved plan and its exact inputs using KMS and AES-GCM.

Only ciphertext is uploaded to GitHub. The KMS encryption context binds the
source SHA, target environment, operation, run ID and creation time. AES-GCM
authenticates the ciphertext and metadata. No data key is printed.
"""

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = Path(__file__).resolve().parents[1]
FILES = {"tfplan", "lambda.zip", "backend.hcl", "app.auto.tfvars.json", "release.json"}
MAX_AGE_SECONDS = 6 * 60 * 60


def aws(arguments):
    result = subprocess.run(["aws", "kms", *arguments, "--output", "json", "--no-cli-pager"],
                            capture_output=True, check=True)
    return json.loads(result.stdout)


def check_metadata(metadata, environment, commit, operation, run_id, project, now=None):
    expected = {"Environment": environment, "Commit": commit, "Operation": operation,
                "Run": str(run_id), "Project": project, "Schema": "1"}
    if set(metadata) != {*expected, "Created"}:
        raise ValueError("Unexpected plan metadata fields")
    if any(metadata[key] != value for key, value in expected.items()):
        raise ValueError("Plan identity does not match the approved run")
    if not re.fullmatch(r"[0-9a-f]{40}", commit) or operation not in {"deploy", "destroy"}:
        raise ValueError("Invalid release identity or operation")
    created = datetime.fromisoformat(metadata["Created"])
    if created.tzinfo is None:
        raise ValueError("Plan creation time must include its timezone")
    age = ((now or datetime.now(timezone.utc)) - created).total_seconds()
    if age < -300 or age > MAX_AGE_SECONDS:
        raise ValueError("Plan is stale or has an invalid creation time; create a new plan")


def seal(build, config, environment, commit, operation, run_id):
    metadata = {"Environment": environment, "Commit": commit, "Operation": operation,
                "Run": str(run_id), "Project": config["project"], "Schema": "1",
                "Created": datetime.now(timezone.utc).isoformat()}
    check_metadata(metadata, environment, commit, operation, run_id, config["project"])
    key = aws(["generate-data-key", "--key-id", config["plan_key_arn"], "--key-spec", "AES_256",
               "--encryption-context", json.dumps(metadata)])
    plaintext = io.BytesIO()
    with zipfile.ZipFile(plaintext, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(FILES):
            archive.write(build / name, arcname=name)
        archive.writestr("metadata.json", json.dumps(metadata, sort_keys=True))
    nonce = os.urandom(12)
    ciphertext = AESGCM(base64.b64decode(key["Plaintext"], validate=True)).encrypt(
        nonce, plaintext.getvalue(), json.dumps(metadata, sort_keys=True).encode())
    (build / "bundle.enc").write_bytes(ciphertext)
    envelope = {"metadata": metadata, "encrypted_key": key["CiphertextBlob"],
                "nonce": base64.b64encode(nonce).decode(),
                "ciphertext_sha256": hashlib.sha256(ciphertext).hexdigest()}
    (build / "envelope.json").write_text(json.dumps(envelope, sort_keys=True) + "\n", encoding="utf-8")


def unseal(build, config, environment, commit, operation, run_id):
    envelope = json.loads((build / "envelope.json").read_text(encoding="utf-8"))
    if set(envelope) != {"metadata", "encrypted_key", "nonce", "ciphertext_sha256"}:
        raise ValueError("Unexpected encryption envelope fields")
    metadata = envelope["metadata"]
    check_metadata(metadata, environment, commit, operation, run_id, config["project"])
    ciphertext = (build / "bundle.enc").read_bytes()
    if len(ciphertext) > 256 * 1024 * 1024 or hashlib.sha256(ciphertext).hexdigest() != envelope["ciphertext_sha256"]:
        raise ValueError("Encrypted plan artifact digest mismatch")
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        encrypted_key = root / "key.bin"
        encrypted_key.write_bytes(base64.b64decode(envelope["encrypted_key"], validate=True))
        key = aws(["decrypt", "--key-id", config["plan_key_arn"], "--ciphertext-blob", f"fileb://{encrypted_key}",
                   "--encryption-context", json.dumps(metadata)])
        plaintext = AESGCM(base64.b64decode(key["Plaintext"], validate=True)).decrypt(
            base64.b64decode(envelope["nonce"], validate=True), ciphertext,
            json.dumps(metadata, sort_keys=True).encode())
        with zipfile.ZipFile(io.BytesIO(plaintext)) as archive:
            if len(archive.infolist()) != len(FILES) + 1 or set(archive.namelist()) != FILES | {"metadata.json"}:
                raise ValueError("Plan bundle contains unexpected or duplicate files")
            if sum(entry.file_size for entry in archive.infolist()) > 256 * 1024 * 1024:
                raise ValueError("Uncompressed plan bundle exceeds the size limit")
            if json.loads(archive.read("metadata.json")) != metadata:
                raise ValueError("Encrypted plan metadata mismatch")
            # Explicit flat names prevent path traversal during extraction.
            for name in FILES:
                (build / name).write_bytes(archive.read(name))
        release = json.loads((build / "release.json").read_text(encoding="utf-8"))
        if release["commit"] != commit:
            raise ValueError("Package release identity mismatch")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("seal", "unseal"))
    parser.add_argument("--environment", required=True, choices=("dev", "prod"))
    parser.add_argument("--commit", required=True)
    parser.add_argument("--operation", required=True, choices=("deploy", "destroy"))
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()
    config = json.loads(os.environ["CONFIG_JSON"])
    operation = seal if args.mode == "seal" else unseal
    operation(ROOT / "build", config, args.environment, args.commit, args.operation, args.run_id)
    print("Saved-plan encryption and identity checks completed")
