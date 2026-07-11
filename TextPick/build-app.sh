#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TextPick"
BUNDLE_ID="com.textpick.app"
VERSION="1.0.0"
BUILD_DIR="$SCRIPT_DIR/.build"
APP_BUNDLE="/tmp/$APP_NAME.app"

echo "📦 Building $APP_NAME.app..."

# ── 1. Build release binary ────────────────────────────────────────────────────
cd "$SCRIPT_DIR"
echo "  → swift build -c release"
swift build -c release

BINARY="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "❌ Build failed — binary not found at $BINARY"
    exit 1
fi

# ── 2. Assemble .app bundle ────────────────────────────────────────────────────
echo "  → Creating bundle structure"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy icon
ICNS="$SCRIPT_DIR/Resources/$APP_NAME.icns"
if [ -f "$ICNS" ]; then
    cp "$ICNS" "$APP_BUNDLE/Contents/Resources/$APP_NAME.icns"
    echo "  → Icon bundled"
fi

# ── 3. Info.plist ──────────────────────────────────────────────────────────────
echo "  → Writing Info.plist"
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- Menu-bar only app: no Dock icon -->
    <key>LSUIElement</key>
    <true/>
    <!-- Retina display support -->
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>TextPick</string>
    <!-- Accessibility permission usage description -->
    <key>NSAccessibilityUsageDescription</key>
    <string>TextPick uses Accessibility to read your selected text without disrupting the clipboard.</string>
    <!-- Required for SF Symbols / AppKit on macOS 13+ -->
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# ── 4. PkgInfo ────────────────────────────────────────────────────────────────
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# ── 5. Ad-hoc code sign ───────────────────────────────────────────────────────
echo "  → Ad-hoc code signing"
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "✅ Built: $APP_BUNDLE"
echo ""

# ── 6. Install or package ─────────────────────────────────────────────────────
if [ "${PACKAGE_ONLY:-0}" = "1" ]; then
    DEST="${DIST_DIR:-$SCRIPT_DIR/../dist}/$APP_NAME.app"
    mkdir -p "$(dirname "$DEST")"
    rm -rf "$DEST"
    cp -R "$APP_BUNDLE" "$DEST"
    rm -rf "$APP_BUNDLE"
    echo "✅ Packaged: $DEST"
else
    echo "  → Installing to /Applications..."
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    rm -rf "$APP_BUNDLE"
    echo "✅ Installed: /Applications/$APP_NAME.app"

    open "/Applications/$APP_NAME.app"
    echo ""
    echo "⚠️  First launch: grant Accessibility in System Settings → Privacy & Security → Accessibility"
    echo "    Then open Settings (click menu bar icon → Settings…) and paste your AI Gateway API key."
fi
