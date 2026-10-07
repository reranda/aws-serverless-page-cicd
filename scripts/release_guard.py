"""Require a deliberate, current-main workflow run before touching AWS."""

import argparse
import os
import subprocess


def validate(ref, event, environment, operation, confirmation, controls_ready):
    if ref != "refs/heads/main" or event != "workflow_dispatch":
        raise ValueError("AWS workflows must be dispatched from main")
    if controls_ready != "true":
        raise ValueError("Configure and verify branch and environment protections first")
    if environment not in {"dev", "prod"} or operation not in {"deploy", "destroy"}:
        raise ValueError("Invalid environment or operation")
    if operation == "destroy" and confirmation != f"DESTROY {environment}":
        raise ValueError(f"Destroy requires the exact confirmation: DESTROY {environment}")


def current_head(repository, expected):
    result = subprocess.run(["gh", "api", f"repos/{repository}/git/ref/heads/main", "--jq", ".object.sha"],
                            check=True, capture_output=True, text=True)
    if result.stdout.strip() != expected:
        raise ValueError("main changed after this run started; create and review a new plan")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--environment", required=True)
    parser.add_argument("--operation", required=True)
    parser.add_argument("--confirmation", default="")
    args = parser.parse_args()
    validate(os.environ["GITHUB_REF"], os.environ["GITHUB_EVENT_NAME"], args.environment, args.operation,
             args.confirmation, os.environ.get("DEPLOYMENT_CONTROLS_READY", ""))
    current_head(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_SHA"])
    print("Main-branch, change-control and operation guards passed")
