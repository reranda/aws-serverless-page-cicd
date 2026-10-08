import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from guard import validate


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.env = {"GITHUB_REF": "refs/heads/main", "GITHUB_EVENT_NAME": "workflow_dispatch",
                    "DEPLOYMENT_CONTROLS_READY": "true", "OPERATION": "deploy"}

    def test_merged_manual_release(self):
        validate(self.env)

    def test_feature_branch_and_pr_rejected(self):
        for key, value in (("GITHUB_REF", "refs/heads/feature"), ("GITHUB_EVENT_NAME", "pull_request")):
            with self.assertRaises(ValueError):
                validate({**self.env, key: value})

    def test_disabled_controls_rejected(self):
        with self.assertRaises(ValueError):
            validate({**self.env, "DEPLOYMENT_CONTROLS_READY": "false"})

    def test_destroy_requires_exact_confirmation(self):
        with self.assertRaises(ValueError):
            validate({**self.env, "OPERATION": "destroy"})
        validate({**self.env, "OPERATION": "destroy", "CONFIRMATION": "DESTROY serverless-page-production"})

