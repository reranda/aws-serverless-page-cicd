import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build import build


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.package = build("a" * 40, self.root / "page.zip")
        with zipfile.ZipFile(self.package) as z:
            z.extractall(self.root)
        spec = importlib.util.spec_from_file_location("packaged_handler", self.root / "handler.py")
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def tearDown(self):
        self.tmp.cleanup()

    def request(self, path="/", method="GET"):
        return self.module.handler({"rawPath": path, "requestContext": {"http": {"method": method}}}, None)

    def test_exact_git_page(self):
        result = self.request()
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(result["body"], (ROOT / "content/index.html").read_text())
        self.assertEqual(result["headers"]["Content-Type"], "text/html; charset=utf-8")

    def test_health_proves_release_and_content(self):
        release = json.loads(self.request("/health")["body"])
        self.assertEqual(release["commit"], "a" * 40)
        self.assertEqual(release["page_sha256"], hashlib.sha256((ROOT / "content/index.html").read_bytes()).hexdigest())

    def test_head_empty_body(self):
        self.assertEqual(self.request(method="HEAD")["body"], "")
        self.assertEqual(self.request("/health", "HEAD")["body"], "")

    def test_path_traversal_and_unknown_routes(self):
        for path in ("/../../etc/passwd", "/missing", "/release.json"):
            self.assertEqual(self.request(path)["statusCode"], 404)

    def test_write_requests_rejected(self):
        self.assertEqual(self.request(method="POST")["statusCode"], 405)

    def test_security_headers(self):
        headers = self.request()["headers"]
        self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        self.assertIn("frame-ancestors 'none'", headers["Content-Security-Policy"])
        self.assertNotIn("'unsafe-inline'", headers["Content-Security-Policy"])

    def test_deterministic_package(self):
        other = build("a" * 40, self.root / "other.zip")
        self.assertEqual(self.package.read_bytes(), other.read_bytes())

    def test_bad_commit_rejected(self):
        with self.assertRaises(ValueError):
            build("main")


if __name__ == "__main__":
    unittest.main()

