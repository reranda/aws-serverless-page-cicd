from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from cryptography.exceptions import InvalidTag

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import plan_bundle
import release_guard


class ReleaseControlTests(unittest.TestCase):
    def test_destroy_guard_is_exact(self):
        with self.assertRaises(ValueError):
            release_guard.validate("refs/heads/main", "workflow_dispatch", "prod", "destroy", "DESTROY dev", "true")
        release_guard.validate("refs/heads/main", "workflow_dispatch", "dev", "destroy", "DESTROY dev", "true")

    def test_feature_branch_and_unconfigured_controls_fail_closed(self):
        for ref, ready in (("refs/heads/feature", "true"), ("refs/heads/main", "false")):
            with self.subTest(ref=ref, ready=ready), self.assertRaises(ValueError):
                release_guard.validate(ref, "workflow_dispatch", "dev", "deploy", "", ready)

    def test_old_plan_and_wrong_environment_are_rejected(self):
        now = datetime.now(timezone.utc)
        metadata = {"Environment": "dev", "Commit": "a" * 40, "Operation": "deploy", "Run": "123",
                    "Project": "slpage", "Schema": "1", "Created": (now - timedelta(hours=7)).isoformat()}
        with self.assertRaises(ValueError):
            plan_bundle.check_metadata(metadata, "dev", "a" * 40, "deploy", "123", "slpage", now=now)
        metadata["Created"] = now.isoformat()
        with self.assertRaises(ValueError):
            plan_bundle.check_metadata(metadata, "prod", "a" * 40, "deploy", "123", "slpage", now=now)

    def test_encrypted_bundle_roundtrip_and_tamper_detection(self):
        # Real AES-GCM encryption; mock only the AWS key exchange to stay offline.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in plan_bundle.FILES:
                (root / name).write_bytes(b"sample plan input")
            (root / "release.json").write_text(json.dumps({"commit": "a" * 40}), encoding="utf-8")
            expected = (root / "tfplan").read_bytes()
            config = {"project": "slpage", "plan_key_arn": "test-key"}
            key_response = {"Plaintext": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", "CiphertextBlob": "dGVzdA=="}
            with patch.object(plan_bundle, "aws", return_value=key_response):
                plan_bundle.seal(root, config, "dev", "a" * 40, "deploy", "123")
                self.assertNotIn(expected, (root / "bundle.enc").read_bytes())
                (root / "tfplan").unlink()
                plan_bundle.unseal(root, config, "dev", "a" * 40, "deploy", "123")
                self.assertEqual((root / "tfplan").read_bytes(), expected)
                encrypted = bytearray((root / "bundle.enc").read_bytes())
                encrypted[-40] ^= 1
                (root / "bundle.enc").write_bytes(encrypted)
                # Update the untrusted hash to prove AES-GCM also rejects tampering.
                envelope = json.loads((root / "envelope.json").read_text())
                envelope["ciphertext_sha256"] = hashlib.sha256(encrypted).hexdigest()
                (root / "envelope.json").write_text(json.dumps(envelope))
                with self.assertRaises(InvalidTag):
                    plan_bundle.unseal(root, config, "dev", "a" * 40, "deploy", "123")


if __name__ == "__main__":
    unittest.main()
