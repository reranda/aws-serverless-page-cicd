"""Report safe OIDC identity fields; never print the signed token."""
import base64
import json
import os
import urllib.request

url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"] + "&audience=sts.amazonaws.com"
request = urllib.request.Request(url, headers={"Authorization": "Bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]})
with urllib.request.urlopen(request, timeout=15) as response:
    token = json.load(response)["value"]
encoded = token.split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
safe = {name: claims[name] for name in ("sub", "aud", "repository_id", "repository_owner_id")}
with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as stream:
    stream.write("### OIDC identity (safe fields only)\n```json\n" + json.dumps(safe, indent=2) + "\n```\n")
print("Recorded subject, audience and immutable repository IDs without exposing a token")
