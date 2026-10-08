"""Print only non-secret OIDC subject/audience claims; never print the token."""
import base64
import json
import os
import urllib.request

url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"] + "&audience=sts.amazonaws.com"
request = urllib.request.Request(url, headers={"Authorization": "Bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]})
with urllib.request.urlopen(request, timeout=15) as response:
    token = json.load(response)["value"]
payload = token.split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({"sub": claims["sub"], "aud": claims["aud"]}, indent=2))

