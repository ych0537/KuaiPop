#!/bin/bash
# One command: build + notarize both variants, commit, push, tag and publish the GitHub Release.
#   ./scripts/publish.sh
# Needs: gh (logged in), scripts/release.env, build/release-notes-<version>.md
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"
NOTES="build/release-notes-$VERSION.md"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
FILES=("build/KuaiPop-$VERSION.zip" "build/KuaiPop-$VERSION.dmg" "build/KuaiPop-Local-$VERSION.zip" "build/KuaiPop-Local-$VERSION.dmg")

command -v gh >/dev/null || { echo "error: gh is not installed" >&2; exit 1; }
[[ -f "$NOTES" ]] || { echo "error: $NOTES not found" >&2; exit 1; }
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "error: release $TAG already exists on GitHub. Bump the version in Resources/Info.plist." >&2
  exit 1
fi

echo "==> 1/4 build, sign and notarize ($VERSION)"
./scripts/release.sh --install
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { echo "error: $f was not created" >&2; exit 1; }
done

echo "==> 2/4 commit and push ($BRANCH)"
git add -A
if ! git diff --cached --quiet; then
  git commit -m "$TAG: Teams メッセージへのリンク、検索先の自動切り替え、ToDo 表示の簡素化" \
    -m "Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DU1X8dCfjKYeHz9bKLfX1o"
fi
git push origin "$BRANCH"

echo "==> 3/4 tag $TAG"
git tag -f "$TAG"
git push -f origin "$TAG"

echo "==> 4/4 GitHub Release"
gh release create "$TAG" "${FILES[@]}" --title "KuaiPop $VERSION" --notes-file "$NOTES"
echo "==> published: $(gh release view "$TAG" --json url --jq .url)"
