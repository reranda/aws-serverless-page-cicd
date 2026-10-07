import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from build import build


class ApplicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory()
        root = Path(cls.workspace.name)
        package = build("a" * 40, root)
        with zipfile.ZipFile(package) as archive:
            archive.extractall(root / "runtime")
        spec = importlib.util.spec_from_file_location("packaged_handler", root / "runtime/handler.py")
        cls.app = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.app)

    @classmethod
    def tearDownClass(cls):
        cls.workspace.cleanup()

    def call(self, path="/", method="GET", headers=None):
        return self.app.handler({"path": path, "httpMethod": method, "headers": headers}, None)

    def test_packaged_page_and_headers(self):
        response = self.call()
        self.assertEqual(response["statusCode"], 200)
        self.assertIn("<!doctype html>", response["body"])
        self.assertEqual(response["headers"]["Content-Type"], "text/html; charset=utf-8")
        self.assertIn("frame-ancestors 'none'", response["headers"]["Content-Security-Policy"])
        self.assertEqual(response["headers"]["X-Content-Type-Options"], "nosniff")

    def test_head_and_conditional_get(self):
        head = self.call(method="HEAD")
        self.assertEqual((head["statusCode"], head["body"]), (200, ""))
        cached = self.call(headers={"IF-NONE-MATCH": head["headers"]["ETag"]})
        self.assertEqual((cached["statusCode"], cached["body"]), (304, ""))

    def test_health_identifies_release(self):
        health = json.loads(self.call("/health")["body"])
        self.assertEqual(health["commit"], "a" * 40)
        self.assertEqual(health["content_sha256"], self.app.PAGE_SHA256)

    def test_unmatched_and_traversal_paths(self):
        for path in ("/missing", "/../handler.py", "/%2e%2e/release.json", "/content/index.html", "/health/extra"):
            with self.subTest(path=path):
                self.assertEqual(self.call(path)["statusCode"], 404)

    def test_methods_are_read_only(self):
        for method in ("POST", "PUT", "PATCH", "DELETE", "OPTIONS"):
            with self.subTest(method=method):
                result = self.call(method=method)
                self.assertEqual(result["statusCode"], 405)
                self.assertEqual(result["headers"]["Allow"], "GET, HEAD")

    def test_logs_do_not_include_untrusted_input(self):
        with patch.object(self.app.LOGGER, "info") as logger:
            self.call("/private-value?token=secret")
            record = json.loads(logger.call_args.args[0])
            self.assertEqual(record["route"], "unmatched")
            self.assertNotIn("private-value", logger.call_args.args[0])


class PackagingTests(unittest.TestCase):
    def test_build_is_deterministic_and_allowlisted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = build("b" * 40, root / "one")
            second = build("b" * 40, root / "two")
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(set(archive.namelist()), {"handler.py", "content/index.html", "release.json"})

    def test_changed_content_changes_release_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "app").mkdir()
            (root / "content").mkdir()
            (root / "app/handler.py").write_text("# test", encoding="utf-8")
            (root / "content/index.html").write_text("<p>first</p>", encoding="utf-8")
            build("c" * 40, root / "build", source=root)
            first = json.loads((root / "build/release.json").read_text())
            (root / "content/index.html").write_text("<p>second</p>", encoding="utf-8")
            build("c" * 40, root / "build", source=root)
            second = json.loads((root / "build/release.json").read_text())
            self.assertNotEqual(first["content_sha256"], second["content_sha256"])

    def test_rejects_non_sha_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                build("main", Path(directory))


if __name__ == "__main__":
    unittest.main()
