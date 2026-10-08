"""Turn non-secret GitHub configuration into Terraform inputs."""
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = {"region", "account_id", "state_bucket", "api_id", "api_endpoint", "api_execution_arn",
            "runtime_role_arn", "alarm_topic_arn", "plan_role_arn", "deploy_role_arn", "deployment_mode"}


def prepare(config, sha):
    if set(config) != REQUIRED:
        raise ValueError("PROJECT_CONFIG fields do not match the bootstrap output")
    if config["deployment_mode"] != os.environ.get("RELEASE_MODE", "reviewed"):
        raise ValueError("Select the release workflow that matches the bootstrap deployment mode")
    build = ROOT / "infrastructure/app/.build"
    build.mkdir(parents=True, exist_ok=True)
    # JSON quoting is also valid for HCL string literals.
    (build / "backend.hcl").write_text(
        f'bucket = {json.dumps(config["state_bucket"])}\n'
        'key = "production/terraform.tfstate"\n'
        f'region = {json.dumps(config["region"])}\n'
        'encrypt = true\nuse_lockfile = true\n'
        f'allowed_account_ids = [{json.dumps(config["account_id"])}]\n'
    )
    variables = {k: v for k, v in config.items() if k not in {"state_bucket", "plan_role_arn", "deploy_role_arn", "deployment_mode"}}
    variables["release_sha"] = sha
    (build / "inputs.tfvars.json").write_text(json.dumps(variables))


if __name__ == "__main__":
    prepare(json.loads(os.environ["PROJECT_CONFIG"]), os.environ["GITHUB_SHA"])

