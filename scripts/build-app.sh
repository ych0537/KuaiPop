#!/bin/bash
# Builds build/KuaiPop.app from the Swift package.
#   ./scripts/build-app.sh            # build only
#   ./scripts/build-app.sh --install  # build, copy to /Applications and launch
# Optional: SIGN_IDENTITY="Developer ID Application" (or "KuaiPop Dev" self-signed) to sign with a
#           stable certificate, so the Accessibility permission survives rebuilds.
#           For a notarized, distributable build use ./scripts/release.sh instead.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"

# SwiftUI macros (@State etc.) need Xcode's toolchain. If xcode-select points at the
# Command Line Tools, swift build fails with "plugin for module 'SwiftUIMacros' not found".
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
  for x in /Applications/Xcode.app /Applications/Xcode*.app; do
    if [[ -d "$x/Contents/Developer" ]]; then
      export DEVELOPER_DIR="$x/Contents/Developer"
      break
    fi
  done
fi
echo "==> toolchain: ${DEVELOPER_DIR:-$(xcode-select -p)}"
APP="build/KuaiPop.app"
SIGN_ID="${SIGN_IDENTITY:--}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/KuaiPop" "$APP/Contents/MacOS/KuaiPop"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" || true
fi

echo "==> codesign ($SIGN_ID)"
if [[ "$SIGN_ID" == "-" ]]; then
  # ad-hoc (local only)
  codesign --force --sign - --identifier com.kuaipop.app "$APP"
else
  # Real certificate (Developer ID / Apple Development): Hardened Runtime + secure timestamp,
  # required for notarization. A stable identity also keeps the Accessibility permission across rebuilds.
  codesign --force --sign "$SIGN_ID" --identifier com.kuaipop.app \
    --options runtime --timestamp --entitlements Resources/KuaiPop.entitlements "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"

echo "==> done: $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x KuaiPop 2>/dev/null || true
  rm -rf /Applications/KuaiPop.app
  cp -R "$APP" /Applications/
  /System/Library/CoreServices/pbs -update || true
  open /Applications/KuaiPop.app
  echo "==> installed to /Applications/KuaiPop.app"
fi
