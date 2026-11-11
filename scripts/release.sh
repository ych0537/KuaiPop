#!/bin/bash
# Developer ID signing + Apple notarization → DMG + ZIP for each variant
#
#   build/KuaiPop-<version>.dmg / .zip         all AI providers (Azure / DeepSeek / Apple / Ollama / OpenAI)
#   build/KuaiPop-Local-<version>.dmg / .zip   Mac on-device AI (Apple Intelligence) only — for company Macs
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
#   ./scripts/release.sh                    # both variants
#   VARIANTS=full ./scripts/release.sh      # only KuaiPop
#   VARIANTS=local ./scripts/release.sh     # only KuaiPop Local
#   ./scripts/release.sh --install          # …and install the full KuaiPop to /Applications
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
VARIANTS="${VARIANTS:-full local}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"

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
echo "==> version:  $VERSION"
echo "==> variants: $VARIANTS"

release_variant() {
  local variant="$1" app_name file_base
  case "$variant" in
    full)  app_name="KuaiPop";       file_base="KuaiPop-$VERSION" ;;
    local) app_name="KuaiPop Local"; file_base="KuaiPop-Local-$VERSION" ;;
    *) echo "error: unknown variant $variant" >&2; exit 1 ;;
  esac
  local app="build/$app_name.app"
  local dmg="build/$file_base.dmg"
  local zip="build/$file_base.zip"

  echo
  echo "################  $app_name  ################"

  # 1. Build + sign the app (Hardened Runtime, timestamp, entitlements)
  VARIANT="$variant" SIGN_IDENTITY="$IDENTITY" ./scripts/build-app.sh

  # 2. DMG with /Applications shortcut
  echo "==> creating $dmg"
  rm -f "$dmg"
  local stage
  stage="$(mktemp -d)"
  cp -R "$app" "$stage/"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "$app_name" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
  rm -rf "$stage"
  codesign --force --sign "$IDENTITY" --timestamp "$dmg"

  # 3. Notarize (the DMG submission also covers the app inside it)
  echo "==> notarizing $dmg (this usually takes 1–5 minutes)"
  local out id
  out="$(xcrun notarytool submit "$dmg" --keychain-profile "$PROFILE" --wait 2>&1)" || true
  echo "$out"
  if ! grep -q "status: Accepted" <<<"$out"; then
    id="$(grep -m1 -E '^\s*id:' <<<"$out" | awk '{print $2}')"
    if [[ -n "$id" ]]; then
      echo "==> notarization log:"
      xcrun notarytool log "$id" --keychain-profile "$PROFILE" || true
    fi
    echo "error: notarization failed ($app_name)" >&2
    exit 1
  fi

  # 4. Staple tickets so Gatekeeper works offline
  xcrun stapler staple "$app"
  xcrun stapler staple "$dmg"

  # 5. Zip of the notarized + stapled app (no mounting / dragging; for Macs without admin rights)
  echo "==> creating $zip"
  rm -f "$zip"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

  echo "==> Gatekeeper check"
  spctl --assess --type execute -vv "$app"
  spctl --assess --type open --context context:primary-signature -vv "$dmg"

  echo "==> done: $dmg"
  echo "==> done: $zip"
}

for v in $VARIANTS; do
  release_variant "$v"
done

echo
echo "==> artifacts:"
ls -lh build/*-"$VERSION".dmg build/*-"$VERSION".zip 2>/dev/null || true

if [[ "${1:-}" == "--install" && " $VARIANTS " == *" full "* ]]; then
  pkill -f "KuaiPop.app/Contents/MacOS/KuaiPop" 2>/dev/null || true
  rm -rf /Applications/KuaiPop.app
  cp -R build/KuaiPop.app /Applications/
  /System/Library/CoreServices/pbs -update || true
  open /Applications/KuaiPop.app
  echo "==> installed to /Applications/KuaiPop.app"
fi
