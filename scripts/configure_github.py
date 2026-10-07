"""Configure solo-lab change controls with GitHub CLI and verify enforcement.

Run as the repository owner. This deliberately fails when the repository's
visibility or GitHub plan does not support the requested protection features.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess

from prepare import validate


def api(path, method="GET", payload=None):
    command = ["gh", "api", path, "--method", method, "-H", "Accept: application/vnd.github+json",
               "-H", "X-GitHub-Api-Version: 2022-11-28"]
    if payload is not None:
        command += ["--input", "-"]
    result = subprocess.run(command, input=None if payload is None else json.dumps(payload),
                            capture_output=True, text=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def variable(repo, name, value):
    subprocess.run(["gh", "variable", "set", name, "--repo", repo, "--body", value],
                   capture_output=True, text=True, check=True)


def verify(repo, owner_id):
    protection = api(f"repos/{repo}/branches/main/protection")
    assert protection["enforce_admins"]["enabled"], "Administrator enforcement is missing"
    assert protection["required_status_checks"]["strict"], "Branch must be current before merge"
    assert "Checks" in protection["required_status_checks"]["contexts"], "Required CI check is missing"
    assert protection["required_pull_request_reviews"] is not None, "Pull request requirement is missing"
    assert protection["required_conversation_resolution"]["enabled"], "Conversation resolution is missing"
    assert protection["required_linear_history"]["enabled"], "Linear history is missing"
    assert not protection["allow_force_pushes"]["enabled"], "Force pushes are allowed"
    assert not protection["allow_deletions"]["enabled"], "Protected branch deletion is allowed"
    for environment in ("dev", "prod"):
        config = api(f"repos/{repo}/environments/{environment}")
        reviewers = [rule for rule in config["protection_rules"] if rule["type"] == "required_reviewers"]
        assert reviewers, f"{environment} has no deployment approval gate"
        assert any(reviewer["reviewer"]["id"] == owner_id for reviewer in reviewers[0]["reviewers"]), "Owner approval gate missing"
        assert not reviewers[0].get("prevent_self_review", False), "Solo deployment would be blocked"
        policy = config["deployment_branch_policy"]
        assert policy and policy["custom_branch_policies"] and not policy["protected_branches"], "Explicit branch allowlist missing"
        branches = api(f"repos/{repo}/environments/{environment}/deployment-branch-policies")["branch_policies"]
        assert len(branches) == 1 and branches[0]["name"] == "main" and branches[0]["type"] == "branch", "Only the main branch may deploy"


def configure(repo, bootstrap):
    repository = api(f"repos/{repo}")
    owner_id = repository["owner"]["id"]
    # Disable the release guard until all controls have been read back successfully.
    variable(repo, "DEPLOYMENT_CONTROLS_READY", "false")
    configs = bootstrap["github_configuration"]["value"]
    for environment in ("dev", "prod"):
        validate(configs[environment], environment)
    expected_prefix = f"repo:{repository['owner']['login']}@{owner_id}/{repository['name']}@{repository['id']}"
    expected = {"plan": expected_prefix + ":ref:refs/heads/main",
                "dev": expected_prefix + ":environment:dev", "prod": expected_prefix + ":environment:prod"}
    if bootstrap["expected_oidc_subjects"]["value"] != expected:
        raise ValueError("Bootstrap OIDC trust does not match this repository's immutable IDs")
    api(f"repos/{repo}", "PATCH", {"allow_squash_merge": True, "allow_merge_commit": False,
                                  "allow_rebase_merge": False, "delete_branch_on_merge": True})
    api(f"repos/{repo}/branches/main/protection", "PUT", {
        "required_status_checks": {"strict": True, "contexts": ["Checks"]},
        "enforce_admins": True,
        "required_pull_request_reviews": {"dismiss_stale_reviews": True, "require_code_owner_reviews": False,
                                          "required_approving_review_count": 0, "require_last_push_approval": False},
        "restrictions": None, "required_linear_history": True, "allow_force_pushes": False,
        "allow_deletions": False, "required_conversation_resolution": True,
    })
    for environment in ("dev", "prod"):
        api(f"repos/{repo}/environments/{environment}", "PUT", {
            "wait_timer": 0, "prevent_self_review": False,
            "reviewers": [{"type": "User", "id": owner_id}],
            "deployment_branch_policy": {"protected_branches": False, "custom_branch_policies": True},
        })
        policies = api(f"repos/{repo}/environments/{environment}/deployment-branch-policies")["branch_policies"]
        if any(policy["name"] != "main" or policy["type"] != "branch" for policy in policies):
            raise ValueError("An existing deployment allowlist is broader than main; review it before continuing")
        if not policies:
            api(f"repos/{repo}/environments/{environment}/deployment-branch-policies", "POST", {"name": "main", "type": "branch"})
    api(f"repos/{repo}/actions/permissions/workflow", "PUT", {
        "default_workflow_permissions": "read", "can_approve_pull_request_reviews": False,
    })
    api(f"repos/{repo}/vulnerability-alerts", "PUT")
    api(f"repos/{repo}/automated-security-fixes", "PUT")
    verify(repo, owner_id)
    for environment in ("dev", "prod"):
        variable(repo, f"{environment.upper()}_CONFIG_JSON", json.dumps(configs[environment], sort_keys=True))
    variable(repo, "DEPLOYMENT_CONTROLS_READY", "true")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="reranda/aws-serverless-page-cicd")
    parser.add_argument("--bootstrap-output", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        raise ValueError("Repository must be owner/name")
    if args.verify_only:
        verify(args.repo, api(f"repos/{args.repo}")["owner"]["id"])
    else:
        if args.bootstrap_output is None:
            parser.error("--bootstrap-output is required unless --verify-only is selected")
        configure(args.repo, json.loads(args.bootstrap_output.read_text(encoding="utf-8-sig")))
    print("Verified solo-lab branch and deployment controls. Independent approval requires another reviewer.")
