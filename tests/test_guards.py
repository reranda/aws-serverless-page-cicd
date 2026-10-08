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

    def test_private_lab_needs_its_own_enable_flag(self):
        lab = {**self.env, "RELEASE_MODE": "private-lab", "DEPLOYMENT_CONTROLS_READY": "false"}
        with self.assertRaises(ValueError):
            validate(lab)
        validate({**lab, "LAB_DEPLOYMENT_READY": "true"})

    def test_private_lab_does_not_authorize_reviewed_release(self):
        with self.assertRaises(ValueError):
            validate({**self.env, "DEPLOYMENT_CONTROLS_READY": "false", "LAB_DEPLOYMENT_READY": "true"})

    def test_unknown_mode_rejected(self):
        with self.assertRaises(ValueError):
            validate({**self.env, "RELEASE_MODE": "unknown"})

    def test_plan_only_private_run(self):
        validate({**self.env, "RELEASE_MODE": "private-lab", "LAB_DEPLOYMENT_READY": "true", "OPERATION": "plan"})
        with self.assertRaises(ValueError):
            validate({**self.env, "OPERATION": "plan"})

    def test_configuration_mode_mismatch_rejected(self):
        with self.assertRaises(ValueError):
            validate({**self.env, "PROJECT_CONFIG": '{"deployment_mode":"private-lab"}'})

