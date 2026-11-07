#!/bin/bash
# Developer ID signing + Apple notarization → build/KuaiPop-<version>.dmg (stapled)
#
# One-time setup (see Readme):
#   1. Developer ID Application certificate in the login keychain
#        security find-identity -v -p codesigning   # should list "Developer ID Application: … (<TEAM_ID>)"
#   2. Notary credentials stored in the keychain:
#        xcrun notarytool store-credentials KuaiPop-notary --apple-id <Apple ID> --team-id <TEAM_ID>
#   3. Your Team ID, either exported or in scripts/release.env (git-ignored):
#        echo 'TEAM_ID=XXXXXXXXXX' > scripts/release.env
#
# Usage:
#   ./scripts/release.sh            # sign, notarize, staple, make DMG
#   ./scripts/release.sh --install  # …and install the notarized app to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

# Local, untracked settings (TEAM_ID, NOTARY_PROFILE, SIGN_IDENTITY …)
if [[ -f scripts/release.env ]]; then
  set -a; source scripts/release.env; set +a
fi
TEAM_ID="${TEAM_ID:-}"
if [[ -z "$TEAM_ID" ]]; then
  echo "error: TEAM_ID is not set." >&2
  echo "       export TEAM_ID=<your Team ID>   or   echo 'TEAM_ID=<your Team ID>' > scripts/release.env" >&2
  echo "       (Team ID: developer.apple.com/account › Membership details)" >&2
  exit 1
fi
PROFILE="${NOTARY_PROFILE:-KuaiPop-notary}"
APP="build/KuaiPop.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/KuaiPop-$VERSION.dmg"

# Pick the Developer ID Application identity for this team.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 \
  | sed -E 's/.*"(.*)".*/\1/')}"
if [[ -z "$IDENTITY" ]]; then
  echo "error: 'Developer ID Application (… $TEAM_ID)' certificate not found in the keychain." >&2
  echo "       Xcode › Settings › Accounts › Manage Certificates… › + › Developer ID Application" >&2
  exit 1
fi
echo "==> identity: $IDENTITY"

# 1. Build + sign the app (Hardened Runtime, timestamp, entitlements)
SIGN_IDENTITY="$IDENTITY" ./scripts/build-app.sh

# 2. DMG with /Applications shortcut
echo "==> creating $DMG"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "KuaiPop" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

# 3. Notarize (the DMG submission also covers the app inside it)
echo "==> notarizing (this usually takes 1–5 minutes)"
OUT="$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1)" || true
echo "$OUT"
if ! grep -q "status: Accepted" <<<"$OUT"; then
  ID="$(grep -m1 -E '^\s*id:' <<<"$OUT" | awk '{print $2}')"
  if [[ -n "$ID" ]]; then
    echo "==> notarization log:"
    xcrun notarytool log "$ID" --keychain-profile "$PROFILE" || true
  fi
  echo "error: notarization failed" >&2
  exit 1
fi

# 4. Staple tickets so Gatekeeper works offline
xcrun stapler staple "$APP"
xcrun stapler staple "$DMG"

echo "==> Gatekeeper check"
spctl --assess --type execute -vv "$APP"
spctl --assess --type open --context context:primary-signature -vv "$DMG"

echo "==> done: $DMG"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x KuaiPop 2>/dev/null || true
  rm -rf /Applications/KuaiPop.app
  cp -R "$APP" /Applications/
  /System/Library/CoreServices/pbs -update || true
  open /Applications/KuaiPop.app
  echo "==> installed to /Applications/KuaiPop.app"
fi
