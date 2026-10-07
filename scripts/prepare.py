"""Validate repository deployment configuration and write private build inputs."""

import argparse
import json
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = {
    "environment", "project", "account_id", "region", "state_bucket", "state_key_arn",
    "plan_key_arn", "plan_role_arn", "deploy_role_arn", "execution_role_arn",
    "rest_api_id", "root_resource_id", "logs_key_arn",
}


def validate(config, environment):
    if set(config) != REQUIRED:
        raise ValueError("Deployment configuration has missing or unexpected keys")
    if environment not in {"dev", "prod"} or config["environment"] != environment:
        raise ValueError("Deployment environment mismatch")
    if not re.fullmatch(r"[0-9]{12}", config["account_id"]):
        raise ValueError("Invalid AWS account ID")
    if not re.fullmatch(r"[a-z][a-z0-9-]{2,19}", config["project"]):
        raise ValueError("Invalid project prefix")
    if not re.fullmatch(r"[a-z]{2}-[a-z]+-[0-9]", config["region"]):
        raise ValueError("Invalid AWS region")
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", config["state_bucket"]):
        raise ValueError("Invalid state bucket")
    for name in ("rest_api_id", "root_resource_id"):
        if not re.fullmatch(r"[a-z0-9]+", config[name]):
            raise ValueError(f"Invalid {name}")
    for name in ("plan_role_arn", "deploy_role_arn", "execution_role_arn"):
        if not config[name].startswith(f"arn:aws:iam::{config['account_id']}:role/") or "\n" in config[name]:
            raise ValueError(f"Invalid {name}")
    for name in ("state_key_arn", "plan_key_arn", "logs_key_arn"):
        if not config[name].startswith(f"arn:aws:kms:{config['region']}:{config['account_id']}:key/") or "\n" in config[name]:
            raise ValueError(f"Invalid {name}")
    return config


def prepare(config, environment, role):
    validate(config, environment)
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    backend = {
        "bucket": config["state_bucket"], "key": f"{environment}/terraform.tfstate",
        "region": config["region"], "encrypt": True, "kms_key_id": config["state_key_arn"],
        "use_lockfile": True, "allowed_account_ids": [config["account_id"]],
    }
    (build / "backend.hcl").write_text("\n".join(f"{key} = {json.dumps(value)}" for key, value in backend.items()) + "\n", encoding="utf-8")
    tfvars = {
        "project": config["project"], "environment": environment,
        "aws_region": config["region"], "expected_account_id": config["account_id"],
        "rest_api_id": config["rest_api_id"], "root_resource_id": config["root_resource_id"],
        "execution_role_arn": config["execution_role_arn"], "logs_kms_key_arn": config["logs_key_arn"],
        "lambda_zip_path": "../../build/lambda.zip",
    }
    (build / "app.auto.tfvars.json").write_text(json.dumps(tfvars, indent=2) + "\n", encoding="utf-8")
    if os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream:
            for key, value in {
                "AWS_REGION": config["region"], "AWS_ACCOUNT_ID": config["account_id"],
                "AWS_ROLE_ARN": config[f"{role}_role_arn"], "PLAN_KEY_ARN": config["plan_key_arn"],
            }.items():
                stream.write(f"{key}={value}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--environment", required=True, choices=("dev", "prod"))
    parser.add_argument("--role", required=True, choices=("plan", "deploy"))
    args = parser.parse_args()
    prepare(json.loads(os.environ["CONFIG_JSON"]), args.environment, args.role)
