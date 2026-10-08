"""Fail closed unless this is an explicitly enabled main-branch release."""
import json
import os
import subprocess
import time
from pathlib import Path


def validate(env):
    if env.get("GITHUB_REF") != "refs/heads/main" or env.get("GITHUB_EVENT_NAME") != "workflow_dispatch":
        raise ValueError("Releases must be manually dispatched from main")
    mode = env.get("RELEASE_MODE", "reviewed")
    if mode == "private-lab":
        if env.get("LAB_DEPLOYMENT_READY") != "true":
            raise ValueError("Complete the private lab configuration before enabling releases")
    elif mode == "reviewed":
        if env.get("DEPLOYMENT_CONTROLS_READY") != "true":
            raise ValueError("Configure and verify GitHub controls before enabling releases")
    else:
        raise ValueError("Unknown release mode")
    if env.get("PROJECT_CONFIG"):
        if json.loads(env["PROJECT_CONFIG"])["deployment_mode"] != mode:
            raise ValueError("Bootstrap configuration does not match this workflow")
    allowed = ("plan", "deploy", "destroy") if mode == "private-lab" else ("deploy", "destroy")
    if env.get("OPERATION") not in allowed:
        raise ValueError("Unknown operation")
    if env.get("OPERATION") == "destroy" and env.get("CONFIRMATION") != "DESTROY serverless-page-production":
        raise ValueError("Destroy confirmation does not match")


if __name__ == "__main__":
    validate(os.environ)
    current = subprocess.check_output(
        ["gh", "api", f'repos/{os.environ["GITHUB_REPOSITORY"]}/git/ref/heads/main', "--jq", ".object.sha"], text=True
    ).strip()
    if current != os.environ["GITHUB_SHA"]:
        raise SystemExit("main changed; generate and review a new plan")
    stamp = Path("infrastructure/app/.build/planned-at")
    if stamp.exists() and time.time() - float(stamp.read_text()) > 21600:
        raise SystemExit("Plan is older than six hours; start a new run")

