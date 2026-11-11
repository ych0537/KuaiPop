#!/bin/bash
# Builds the app bundle from the Swift package.
#
#   ./scripts/build-app.sh                    # build/KuaiPop.app        (all AI providers)
#   VARIANT=local ./scripts/build-app.sh      # build/KuaiPop Local.app  (Mac on-device AI only)
#   ./scripts/build-app.sh --install          # …and copy to /Applications and launch
#
# Optional: SIGN_IDENTITY="Developer ID Application" (or "KuaiPop Dev" self-signed) to sign with a
#           stable certificate, so the Accessibility permission survives rebuilds.
#           For notarized, distributable builds use ./scripts/release.sh instead.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
VARIANT="${VARIANT:-full}"

case "$VARIANT" in
  full)
    APP_NAME="KuaiPop"; BUNDLE_ID="com.kuaipop.app"
    SCRATCH=".build"; MIN_OS=""; SWIFT_FLAGS=()
    ;;
  local)
    # Only Apple Intelligence (FoundationModels) — needs macOS 26 and Xcode 26 to build.
    APP_NAME="KuaiPop Local"; BUNDLE_ID="com.kuaipop.app.local"
    SCRATCH=".build-local"; MIN_OS="26.0"; SWIFT_FLAGS=(-Xswiftc -DLOCAL_ONLY)
    ;;
  *) echo "error: VARIANT must be 'full' or 'local'" >&2; exit 1 ;;
esac

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
echo "==> variant: $VARIANT ($APP_NAME)"

APP="build/$APP_NAME.app"
SIGN_ID="${SIGN_IDENTITY:--}"
PB=/usr/libexec/PlistBuddy

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --scratch-path "$SCRATCH" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" --scratch-path "$SCRATCH" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/KuaiPop" "$APP/Contents/MacOS/KuaiPop"
PLIST="$APP/Contents/Info.plist"
cp Resources/Info.plist "$PLIST"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Variant-specific Info.plist values (separate bundle ID = separate settings, can be installed side by side)
$PB -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
$PB -c "Set :CFBundleName $APP_NAME" "$PLIST"
$PB -c "Set :CFBundleDisplayName $APP_NAME" "$PLIST"
if [[ -n "$MIN_OS" ]]; then
  $PB -c "Set :LSMinimumSystemVersion $MIN_OS" "$PLIST"
fi
i=0
while $PB -c "Print :NSServices:$i" "$PLIST" >/dev/null 2>&1; do
  title="$($PB -c "Print :NSServices:$i:NSMenuItem:default" "$PLIST")"
  $PB -c "Set :NSServices:$i:NSMenuItem:default ${title/KuaiPop/$APP_NAME}" "$PLIST"
  $PB -c "Set :NSServices:$i:NSPortName $APP_NAME" "$PLIST"
  i=$((i + 1))
done

echo "==> codesign ($SIGN_ID)"
if [[ "$SIGN_ID" == "-" ]]; then
  # ad-hoc (local only)
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
else
  # Real certificate (Developer ID / Apple Development): Hardened Runtime + secure timestamp,
  # required for notarization. A stable identity also keeps the Accessibility permission across rebuilds.
  codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" \
    --options runtime --timestamp --entitlements Resources/KuaiPop.entitlements "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"

echo "==> done: $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -f "$APP_NAME.app/Contents/MacOS/KuaiPop" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  /System/Library/CoreServices/pbs -update || true
  open "/Applications/$APP_NAME.app"
  echo "==> installed to /Applications/$APP_NAME.app"
fi
