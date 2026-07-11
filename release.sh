#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CASK="$SCRIPT_DIR/Casks/textpick.rb"
DIST_DIR="$SCRIPT_DIR/dist"

VERSION="${1:-$(grep '^VERSION=' "$SCRIPT_DIR/TextPick/build-app.sh" | cut -d'"' -f2)}"
PUBLISH="${PUBLISH:-0}"
if [ "${2:-}" = "--publish" ]; then PUBLISH=1; fi

ZIP="$DIST_DIR/TextPick-$VERSION.zip"

echo "📦 Building TextPick $VERSION..."
PACKAGE_ONLY=1 DIST_DIR="$DIST_DIR" "$SCRIPT_DIR/TextPick/build-app.sh"

echo "  → Creating zip"
ditto -c -k --keepParent "$DIST_DIR/TextPick.app" "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo ""
echo "✅ $ZIP"
echo "   sha256: $SHA"

# Update cask
sed -i '' "s/version \".*\"/version \"$VERSION\"/" "$CASK"
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" "$CASK"
echo "  → Updated $CASK"

if [ "$PUBLISH" = "1" ]; then
    echo "  → Publishing GitHub release v$VERSION"
    if gh release view "v$VERSION" &>/dev/null; then
        gh release upload "v$VERSION" "$ZIP" --clobber
    else
        gh release create "v$VERSION" "$ZIP" \
            --title "v$VERSION" \
            --notes "TextPick $VERSION — macOS menu bar app for LLM text processing."
    fi
    echo ""
    echo "✅ Published: https://github.com/lenohard/textpick/releases/tag/v$VERSION"
else
    echo ""
    echo "To publish:"
    echo "  git add Casks/textpick.rb && git commit -m \"chore: update cask for v$VERSION\""
    echo "  git push"
    echo "  ./release.sh $VERSION --publish"
fi

echo ""
echo "Install:"
echo "  brew install --cask https://raw.githubusercontent.com/lenohard/textpick/main/Casks/textpick.rb"
