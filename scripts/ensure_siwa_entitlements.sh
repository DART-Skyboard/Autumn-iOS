#!/usr/bin/env bash
# After archive: if signed binary lacks applesignin, re-sign with explicit entitlements.
set -euo pipefail
APP="${1:?app path}"
OUT="${2:-${RUNNER_TEMP:-/tmp}/siwa-ents}"
KEYCHAIN="${3:-}"
mkdir -p "$OUT"

codesign --display --entitlements :- "$APP" > "$OUT/pre-resign-binary.xml" 2>/dev/null || true
if grep -q "com.apple.developer.applesignin" "$OUT/pre-resign-binary.xml"; then
  echo "ensure_siwa: packaging kept applesignin"
  exit 0
fi

echo "ensure_siwa: packaging stripped applesignin — re-signing"
cat > "$OUT/resign.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key>
	<string>L7AHWS9Q6V.com.dartmeadow.autumn</string>
	<key>beta-reports-active</key>
	<true/>
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
	<key>com.apple.developer.team-identifier</key>
	<string>L7AHWS9Q6V</string>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>get-task-allow</key>
	<false/>
	<key>keychain-access-groups</key>
	<array>
		<string>L7AHWS9Q6V.com.dartmeadow.autumn</string>
	</array>
</dict>
</plist>
PLIST

IDENTITY=$(security find-identity -v -p codesigning ${KEYCHAIN:+"$KEYCHAIN"} 2>/dev/null | awk -F'"' '/iPhone Distribution|Apple Distribution/ {print $2; exit}')
if [ -z "$IDENTITY" ] && [ -n "$KEYCHAIN" ]; then
  IDENTITY=$(security find-identity -v -p codesigning -keychain "$KEYCHAIN" | awk -F'"' '/Distribution/ {print $2; exit}')
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Distribution/ {print $2; exit}')
fi
echo "ensure_siwa: identity=$IDENTITY"
test -n "$IDENTITY"

CODESIGN_ARGS=(--force --sign "$IDENTITY" --entitlements "$OUT/resign.entitlements" --generate-entitlement-der)
if [ -n "$KEYCHAIN" ]; then
  CODESIGN_ARGS+=(--keychain "$KEYCHAIN")
fi
/usr/bin/codesign "${CODESIGN_ARGS[@]}" "$APP"
codesign --display --entitlements :- "$APP" > "$OUT/post-resign-binary.xml" 2>/dev/null || true
grep -q "com.apple.developer.applesignin" "$OUT/post-resign-binary.xml"
echo "ensure_siwa: re-sign OK — applesignin present"