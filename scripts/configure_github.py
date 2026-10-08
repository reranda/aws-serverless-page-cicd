"""Configure controls using your locally authenticated GitHub CLI, then verify them.

Default: an independent reviewer, including no self approval for deployments.
--solo-lab explicitly allows self approval of deployments and sets PR approval count to zero.
Neither mode changes repository visibility or invites collaborators.
"""
import argparse
import json
import subprocess
from pathlib import Path


def api(path, method="GET", data=None):
    command = ["gh", "api", path, "--method", method]
    if data is not None:
        command += ["--input", "-"]
    result = subprocess.run(command, input=json.dumps(data) if data is not None else None,
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def configure(repo, reviewer, config, solo):
    if json.loads(config.read_text(encoding="utf-8-sig")).get("deployment_mode") != "reviewed":
        raise ValueError("Use deployment_mode = reviewed before configuring reviewed releases")
    # Disable releases first; leave them disabled on ANY failed setup operation.
    subprocess.run(["gh", "variable", "set", "DEPLOYMENT_CONTROLS_READY", "--repo", repo, "--body", "false"], check=True)
    metadata = api(f"repos/{repo}")
    viewer = api("user")["login"]
    review_user = api(f"users/{reviewer}")
    if not solo:
        if reviewer.casefold() == viewer.casefold():
            raise ValueError("Team mode requires an independent reviewer. Use --solo-lab explicitly for a solo demonstration.")
        permission = api(f"repos/{repo}/collaborators/{reviewer}/permission")["permission"]
        if permission not in {"write", "admin", "maintain"}:
            raise ValueError("The reviewer needs existing write access; this script does not invite users.")
    mode = "solo demonstration" if solo else "independent review"
    print(f"Configuring {repo}: {mode}; visibility remains {metadata['visibility']}")
    api(f"repos/{repo}", "PATCH", {"allow_squash_merge": True, "allow_merge_commit": False,
                                     "allow_rebase_merge": False, "delete_branch_on_merge": True})
    expected = 0 if solo else 1
    api(f"repos/{repo}/branches/main/protection", "PUT", {
        "required_status_checks": {"strict": True, "checks": [{"context": "Checks", "app_id": 15368}]},
        "enforce_admins": True,
        "required_pull_request_reviews": {"dismiss_stale_reviews": True,
            "require_code_owner_reviews": False, "required_approving_review_count": expected},
        "restrictions": None, "required_conversation_resolution": True,
        "required_linear_history": True, "allow_force_pushes": False, "allow_deletions": False
    })
    for environment in ("production-plan", "production"):
        body = {"deployment_branch_policy": {"protected_branches": False, "custom_branch_policies": True}}
        if environment == "production":
            body.update({"reviewers": [{"type": "User", "id": review_user["id"]}],
                         "prevent_self_review": not solo, "can_admins_bypass": False})
        api(f"repos/{repo}/environments/{environment}", "PUT", body)
        policies_path = f"repos/{repo}/environments/{environment}/deployment-branch-policies"
        existing = api(policies_path)["branch_policies"]
        for policy in existing:
            if policy["name"] != "main" or policy["type"] != "branch":
                api(f"{policies_path}/{policy['id']}", "DELETE")
        if not any(p["name"] == "main" and p["type"] == "branch" for p in existing):
            api(policies_path, "POST", {"name": "main", "type": "branch"})
    protection = api(f"repos/{repo}/branches/main/protection")
    assert protection["enforce_admins"]["enabled"]
    assert protection["required_pull_request_reviews"]["required_approving_review_count"] == expected
    assert protection["required_status_checks"]["strict"]
    assert {"context": "Checks", "app_id": 15368} in protection["required_status_checks"]["checks"]
    assert protection["required_conversation_resolution"]["enabled"]
    assert protection["required_pull_request_reviews"]["dismiss_stale_reviews"]
    assert not protection["allow_force_pushes"]["enabled"]
    assert not protection["allow_deletions"]["enabled"]
    for environment in ("production-plan", "production"):
        value = api(f"repos/{repo}/environments/{environment}")
        assert value["deployment_branch_policy"] == {"protected_branches": False, "custom_branch_policies": True}
        policies = api(f"repos/{repo}/environments/{environment}/deployment-branch-policies")["branch_policies"]
        assert len(policies) == 1 and policies[0]["name"] == "main" and policies[0]["type"] == "branch"
        if environment == "production":
            rule = next(r for r in value["protection_rules"] if r["type"] == "required_reviewers")
            assert any(r["reviewer"]["id"] == review_user["id"] for r in rule["reviewers"])
            assert rule.get("prevent_self_review", False) == (not solo)
            assert not value["can_admins_bypass"]
    subprocess.run(["gh", "variable", "set", "PROJECT_CONFIG", "--repo", repo, "--body", config.read_text()], check=True)
    subprocess.run(["gh", "variable", "set", "DEPLOYMENT_CONTROLS_READY", "--repo", repo, "--body", "true"], check=True)
    print("GitHub controls verified. Enable Terraform CI trust next, following docs/setup.md.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="reranda/aws-serverless-page-cicd")
    parser.add_argument("--reviewer", required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--solo-lab", action="store_true")
    args = parser.parse_args()
    configure(args.repo, args.reviewer, args.config, args.solo_lab)

