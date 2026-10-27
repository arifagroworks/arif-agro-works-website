#!/usr/bin/env python3
"""Owner-side narrow Auth configuration update; never prints credentials/config."""
import json
import os
import urllib.request
import urllib.error

PROJECT = "qfydekphbdpvvczhimjs"
URL = f"https://api.supabase.com/v1/projects/{PROJECT}/config/auth"

def enable(token, send=urllib.request.urlopen):
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
    request = urllib.request.Request(URL, data=b'{"password_hibp_enabled":true}', headers=headers, method="PATCH")
    with send(request, timeout=20) as response:
        response.read()
    with send(urllib.request.Request(URL, headers=headers), timeout=20) as response:
        state = json.load(response)
    if state.get("password_hibp_enabled") is not True:
        raise RuntimeError("Password protection did not become enabled")
    return True

if __name__ == "__main__":
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
    if not token:
        raise SystemExit("Set an owner SUPABASE_ACCESS_TOKEN locally; do not paste it in chat.")
    try:
        enable(token)
    except urllib.error.HTTPError as error:
        raise SystemExit(f"Owner Auth configuration request failed (HTTP {error.code}). Check owner access and plan; no upgrade was attempted.")
    print("Leaked-password protection is enabled and verified.")
