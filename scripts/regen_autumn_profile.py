#!/usr/bin/env python3
"""Regenerate INVALID AutumnGitHubFlow IOS_APP_STORE profile via ASC API."""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import jwt
import requests

KEY_ID = os.environ.get("ASC_KEY_ID", "NQXQ595W59")
ISSUER = os.environ["ASC_ISSUER_ID"]
KEY_PATH = os.environ["ASC_KEY_PATH"]
API = "https://api.appstoreconnect.apple.com/v1"

AUTUMN_BUNDLE = "com.dartmeadow.autumn"
PROFILE_NAME = "AutumnGitHubFlow"
OUT_DIR = Path(os.environ.get("REGEN_OUT", "/tmp/regen-profile"))
OUT_DIR.mkdir(parents=True, exist_ok=True)


def make_token() -> str:
    private_key = Path(KEY_PATH).read_text()
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"alg": "ES256", "kid": KEY_ID, "typ": "JWT"},
    )


TOKEN = make_token()
H = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}


def req(method: str, path: str, **kwargs):
    url = path if path.startswith("http") else f"{API}{path}"
    r = requests.request(method, url, headers=H, timeout=90, **kwargs)
    print(f"{method} {url} -> {r.status_code}")
    if r.status_code >= 400:
        print(r.text[:3000])
        r.raise_for_status()
    if r.status_code == 204 or not r.content:
        return None
    return r.json()


def get_all(path: str, params=None):
    params = dict(params or {})
    params.setdefault("limit", 200)
    page = req("GET", path, params=params)
    data = list(page.get("data") or [])
    while page.get("links", {}).get("next"):
        page = req("GET", page["links"]["next"])
        data.extend(page.get("data") or [])
    return data


def decode_profile(raw: bytes, label: str) -> str:
    pp = OUT_DIR / f"{label}.mobileprovision"
    pp.write_bytes(raw)
    xml = subprocess.check_output(
        ["openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", str(pp)],
        stderr=subprocess.DEVNULL,
    ).decode("utf-8", errors="replace")
    (OUT_DIR / f"{label}.plist.xml").write_text(xml)
    return xml


def main() -> int:
    report = []

    def log(s=""):
        print(s)
        report.append(s)

    log("# Regen AutumnGitHubFlow")
    bundles = get_all("/bundleIds", {"filter[identifier]": AUTUMN_BUNDLE})
    if not bundles:
        all_b = get_all("/bundleIds")
        bundles = [b for b in all_b if b.get("attributes", {}).get("identifier") == AUTUMN_BUNDLE]
    if not bundles:
        log("FATAL: Autumn bundle not found")
        return 1
    bundle = bundles[0]
    bundle_id = bundle["id"]
    log(f"bundleId={bundle_id} identifier={bundle['attributes'].get('identifier')}")

    certs = get_all("/certificates")
    dist = [
        c
        for c in certs
        if c.get("attributes", {}).get("certificateType")
        in ("IOS_DISTRIBUTION", "DISTRIBUTION", "APPLE_DISTRIBUTION")
    ]
    log(f"distribution certs: {len(dist)}")
    for c in dist:
        a = c["attributes"]
        log(f"- cert id={c['id']} type={a.get('certificateType')} name={a.get('name')} exp={a.get('expirationDate')}")
    if not dist:
        log("FATAL: no distribution certificate")
        return 1
    # Prefer non-expired; pick latest expiration
    dist.sort(key=lambda c: c["attributes"].get("expirationDate") or "", reverse=True)
    cert_id = dist[0]["id"]
    log(f"using certificate {cert_id}")

    profiles = get_all("/profiles")
    autumn_profiles = [
        p
        for p in profiles
        if p.get("attributes", {}).get("name") == PROFILE_NAME
        or (
            p.get("attributes", {}).get("uuid") == "d5e965c9-84bd-4151-9157-785629bc3d1f"
        )
    ]
    # Also match by bundle via detail later
    for p in profiles:
        name = p.get("attributes", {}).get("name", "")
        if "Autumn" in name and p not in autumn_profiles:
            autumn_profiles.append(p)

    log(f"existing Autumn-ish profiles: {len(autumn_profiles)}")
    for p in autumn_profiles:
        a = p["attributes"]
        log(f"- {a.get('name')} id={p['id']} uuid={a.get('uuid')} state={a.get('profileState')} type={a.get('profileType')}")

    # Delete INVALID AutumnGitHubFlow (name conflict on create)
    for p in list(autumn_profiles):
        a = p["attributes"]
        if a.get("name") == PROFILE_NAME or a.get("uuid") == "d5e965c9-84bd-4151-9157-785629bc3d1f":
            log(f"DELETE profile {p['id']} ({a.get('name')} state={a.get('profileState')})")
            req("DELETE", f"/profiles/{p['id']}")
            log("deleted")

    body = {
        "data": {
            "type": "profiles",
            "attributes": {
                "name": PROFILE_NAME,
                "profileType": "IOS_APP_STORE",
            },
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
            },
        }
    }
    log("CREATE IOS_APP_STORE profile AutumnGitHubFlow")
    created = req("POST", "/profiles", json=body)
    pdata = created["data"]
    attrs = pdata["attributes"]
    uuid = attrs["uuid"]
    state = attrs.get("profileState")
    content_b64 = attrs.get("profileContent")
    log(f"created id={pdata['id']} uuid={uuid} state={state}")

    raw = base64.b64decode(content_b64)
    xml = decode_profile(raw, "AutumnGitHubFlow-new")
    has_siwa = "com.apple.developer.applesignin" in xml
    has_ubi = "ubiquity" in xml.lower()
    has_aps = "aps-environment" in xml
    log(f"HAS applesignin={has_siwa} aps={has_aps} ubiquity={has_ubi}")

    # Write outputs
    (OUT_DIR / "profile.mobileprovision").write_bytes(raw)
    (OUT_DIR / "PROVISIONING_PROFILE_BASE64.txt").write_text(base64.b64encode(raw).decode())
    (OUT_DIR / "uuid.txt").write_text(uuid + "\n")
    meta = {
        "uuid": uuid,
        "profileState": state,
        "profileId": pdata["id"],
        "name": PROFILE_NAME,
        "certificateId": cert_id,
        "bundleId": bundle_id,
        "has_siwa": has_siwa,
        "has_aps": has_aps,
        "has_ubiquity": has_ubi,
    }
    (OUT_DIR / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    (OUT_DIR / "report.md").write_text("\n".join(report) + "\n")

    if not has_siwa:
        log("WARN: new profile missing SIWA entitlement")
        return 2
    if state != "ACTIVE":
        log(f"WARN: profile state is {state}, expected ACTIVE")
        return 3
    log("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
