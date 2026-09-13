#!/usr/bin/env bash
# Behind-the-scenes SIWA signing validation (no archive / no TestFlight).
# Compares: App entitlements file ↔ provisioning-profile Entitlements ↔ Ashtree minimal set.
# Optionally queries ASC bundleIds capabilities when APP_STORE_CONNECT_* secrets are present.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ENT="$ROOT/Sources/AutumnApp/AutumnApp.entitlements"
OUT_DIR="${RUNNER_TEMP:-/tmp}/siwa-validate"
mkdir -p "$OUT_DIR"

echo "=== Autumn app entitlements (repo file) ==="
plutil -p "$APP_ENT" 2>/dev/null || cat "$APP_ENT"

# Ashtree working minimal set (from DART-Skyboard/AshtreeIDE-iOS AshtreeIDE.entitlements)
ASHTREE_KEYS=(
  "com.apple.developer.applesignin"
  "com.apple.security.network.client"
  "keychain-access-groups"
)

echo ""
echo "=== AshtreeIDE working SIWA entitlement keys (reference) ==="
printf '  - %s\n' "${ASHTREE_KEYS[@]}"

if [[ -z "${PROVISIONING_PROFILE_BASE64:-}" ]]; then
  echo "ERROR: PROVISIONING_PROFILE_BASE64 not set" >&2
  exit 1
fi

PP="$OUT_DIR/AutumnGitHubFlow.mobileprovision"
echo "$PROVISIONING_PROFILE_BASE64" | base64 --decode > "$PP"
echo ""
echo "=== Profile size ==="
wc -c "$PP"

# Decode CMS → plist (macOS security cms; Linux: openssl smime fallback)
PP_PLIST="$OUT_DIR/profile.plist"
if command -v security >/dev/null 2>&1; then
  security cms -D -i "$PP" > "$PP_PLIST"
elif command -v openssl >/dev/null 2>&1; then
  # portable-ish extract between plist markers
  openssl smime -inform DER -verify -noverify -in "$PP" 2>/dev/null > "$PP_PLIST" \
    || python3 - <<'PY' "$PP" "$PP_PLIST"
import sys
raw=open(sys.argv[1],'rb').read()
start=raw.find(b'<?xml')
end=raw.rfind(b'</plist>')+8
open(sys.argv[2],'wb').write(raw[start:end])
PY
else
  python3 - <<'PY' "$PP" "$PP_PLIST"
import sys
raw=open(sys.argv[1],'rb').read()
start=raw.find(b'<?xml')
end=raw.rfind(b'</plist>')+8
open(sys.argv[2],'wb').write(raw[start:end])
PY
fi

echo ""
echo "=== Profile metadata ==="
if command -v plutil >/dev/null 2>&1; then
  echo "Name: $(plutil -extract Name raw "$PP_PLIST" 2>/dev/null || true)"
  echo "UUID: $(plutil -extract UUID raw "$PP_PLIST" 2>/dev/null || true)"
  echo "Team: $(plutil -extract TeamIdentifier.0 raw "$PP_PLIST" 2>/dev/null || true)"
  echo "AppID: $(plutil -extract Entitlements.application-identifier raw "$PP_PLIST" 2>/dev/null || true)"
  echo ""
  echo "=== Profile Entitlements (full) ==="
  plutil -extract Entitlements xml1 -o "$OUT_DIR/profile-ents.xml" "$PP_PLIST"
  plutil -p "$OUT_DIR/profile-ents.xml"
else
  python3 - <<'PY' "$PP_PLIST"
import plistlib,sys,json
d=plistlib.loads(open(sys.argv[1],'rb').read())
ents=d.get('Entitlements',{})
print('Name:', d.get('Name'))
print('UUID:', d.get('UUID'))
print('Team:', d.get('TeamIdentifier'))
print('AppID:', ents.get('application-identifier'))
print('=== Profile Entitlements (full) ===')
print(json.dumps(ents, indent=2, default=str))
open('/tmp/siwa_profile_ents.json','w').write(json.dumps(ents, indent=2, default=str))
PY
fi

echo ""
echo "=== Diff: app entitlements keys vs profile-granted keys ==="
python3 - <<'PY' "$APP_ENT" "$PP_PLIST"
import plistlib, sys, xml.etree.ElementTree as ET

def load_plist(path):
    with open(path,'rb') as f:
        return plistlib.load(f)

app = load_plist(sys.argv[1])
prof = load_plist(sys.argv[2])
ents = prof.get('Entitlements', {})

# Keys that matter for SIWA poison lesson (ignore application-identifier / team-id / get-task-allow)
IGNORE = {
  'application-identifier', 'com.apple.developer.team-identifier',
  'get-task-allow', 'beta-reports-active', 'com.apple.developer.aps-environment',
}
# Note: aps-environment in profile may appear as aps-environment key

app_keys = set(app.keys())
prof_keys = set(ents.keys()) - IGNORE
# Normalize: profile uses same key names as entitlements file
extra_in_app = sorted(app_keys - set(ents.keys()))
missing_from_app = sorted(k for k in ('com.apple.developer.applesignin','com.apple.security.network.client','keychain-access-groups') if k not in app_keys)
ashtree_only = {'com.apple.developer.applesignin','com.apple.security.network.client','keychain-access-groups'}
autumn_extra_vs_ashtree = sorted(app_keys - ashtree_only)

print('App entitlement keys:', sorted(app_keys))
print('Profile entitlement keys:', sorted(ents.keys()))
print()
print('App keys NOT in profile (POISON RISK if non-empty):', extra_in_app if extra_in_app else '(none)')
print('Ashtree SIWA keys missing from app:', missing_from_app if missing_from_app else '(none)')
print('Autumn app keys beyond Ashtree minimal set:', autumn_extra_vs_ashtree if autumn_extra_vs_ashtree else '(none)')
print()
# Detail applesignin / aps / ubiquity
for k in sorted(set(list(app_keys)+list(ents.keys()))):
    if any(x in k for x in ('apple','aps','ubiquity','icloud','keychain','network')):
        print(f'  KEY {k}')
        print(f'    app:     {app.get(k, "<absent>")}')
        print(f'    profile: {ents.get(k, "<absent>")}')

poison = [k for k in extra_in_app if k not in IGNORE]
if poison:
    print()
    print('RESULT: MISMATCH — app requests entitlements the profile does not grant:')
    for k in poison:
        print(f'  - {k}')
    print('Arc Lake lesson: unpermitted entitlements can invalidate the whole blob incl. applesignin.')
    open('/tmp/siwa_validate_result.txt','w').write('MISMATCH\n')
else:
    print()
    print('RESULT: App entitlement keys ⊆ profile Entitlements (no unpermitted-key poison).')
    if autumn_extra_vs_ashtree:
        print('NOTE: Autumn still requests extra vs Ashtree minimal (aps/iCloud). That is OK for SIWA')
        print('ONLY if the profile grants those keys (shown above). Extra granted keys are not the Arc Lake poison mode.')
    open('/tmp/siwa_validate_result.txt','w').write('OK_SUBSET\n')
PY

echo ""
echo "=== ASC bundleId capabilities (optional) ==="
if [[ -n "${APP_STORE_CONNECT_API_KEY_CONTENT:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  KEY_ID="${APP_STORE_CONNECT_API_KEY_ID:-NQXQ595W59}"
  mkdir -p "$HOME/.appstoreconnect/private_keys"
  KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
  printf '%s' "$APP_STORE_CONNECT_API_KEY_CONTENT" > "$KEY_PATH"
  chmod 600 "$KEY_PATH"
  python3 - <<'PY' "$KEY_PATH" "$KEY_ID" "${APP_STORE_CONNECT_ISSUER_ID}"
import jwt, time, urllib.request, urllib.error, json, sys, ssl
key_path, key_id, issuer = sys.argv[1], sys.argv[2], sys.argv[3]
pk=open(key_path).read()
token=jwt.encode({"iss":issuer,"iat":int(time.time()),"exp":int(time.time())+1200,"aud":"appstoreconnect-v1"},
                 pk, algorithm="ES256", headers={"kid":key_id})
if isinstance(token,bytes): token=token.decode()
ctx=ssl.create_default_context()

def asc(path):
    req=urllib.request.Request(f"https://api.appstoreconnect.apple.com/v1{path}",
        headers={"Authorization":f"Bearer {token}","Content-Type":"application/json"})
    try:
        with urllib.request.urlopen(req, context=ctx) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        print(f"ASC {path} -> {e.code}: {e.read().decode()[:400]}")
        return None

# Find Autumn + Ashtree bundle IDs
for ident in ("com.dartmeadow.autumn", "DART-Meadow-LLC.AshtreeIDE"):
    data=asc(f"/bundleIds?filter[identifier]={ident}&limit=5")
    if not data or not data.get("data"):
        print(f"bundleId {ident}: NOT FOUND")
        continue
    bid=data["data"][0]
    print(f"bundleId {ident}: id={bid['id']} name={bid['attributes'].get('name')} platform={bid['attributes'].get('platform')}")
    caps=asc(f"/bundleIds/{bid['id']}/bundleIdCapabilities?limit=50")
    if not caps: continue
    print(f"  capabilities ({len(caps.get('data',[]))}):")
    for c in caps.get("data",[]):
        attrs=c.get("attributes",{})
        print(f"    - {attrs.get('capabilityType')} enabled={attrs.get('settings') is not None or True} settings={attrs.get('settings')}")
PY
else
  echo "(skipped — ASC secrets not in env)"
fi

echo ""
echo "=== Done ==="
cat /tmp/siwa_validate_result.txt 2>/dev/null || true
