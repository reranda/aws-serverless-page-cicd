"""Save repository variables for an explicitly selected private, unreviewed lab."""
import argparse
import json
import subprocess
from pathlib import Path


def main(repo, path):
    def variable(name, value):
        subprocess.run(["gh", "variable", "set", name, "--repo", repo, "--body", value], check=True)
    variable("LAB_DEPLOYMENT_READY", "false")
    config = json.loads(path.read_text(encoding="utf-8-sig"))
    if config.get("deployment_mode") != "private-lab":
        raise ValueError("Bootstrap must use deployment_mode = private-lab")
    metadata = json.loads(subprocess.check_output(["gh", "api", f"repos/{repo}"], text=True))
    if metadata["visibility"] != "private":
        raise ValueError("This script is specifically for the private lab mode")
    variable("DEPLOYMENT_CONTROLS_READY", "false")
    variable("PROJECT_CONFIG", json.dumps(config))
    variable("LAB_DEPLOYMENT_READY", "true")
    print("Private lab configuration saved. No environment or review protection was configured.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="reranda/aws-serverless-page-cicd")
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    main(args.repo, args.config)

