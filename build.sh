#!/usr/bin/env bash
# build.sh — deterministic build, sign, and install for ClaudeUsage
# Usage: ./build.sh [--identity "Your Cert Name"]
#
# Signs with the SAME identity on every run so macOS keychain ACL
# "Always Allow" grants persist across rebuilds.
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeUsage"
BUNDLE_ID="com.stoneros.claude-usage"
STAGED="$PROJ_DIR/.staged/$APP_NAME.app"
INSTALLED="/Applications/$APP_NAME.app"
LAUNCHAGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
SOURCE_PLIST="$PROJ_DIR/$APP_NAME/Info.plist"
ICON_SRC="$PROJ_DIR/build/$APP_NAME.app/Contents/Resources/AppIcon.icns"

# --- Identity selection ---
if [ -z "${SIGN_IDENTITY:-}" ]; then
    # Prefer Developer ID (most durable ACL), then Apple Development
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -m1 "Developer ID Application" \
        | sed -E 's/.*"(.+)".*/\1/' || true)
fi
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -m1 "Apple Development" \
        | sed -E 's/.*"(.+)".*/\1/' || true)
fi
if [ -z "${SIGN_IDENTITY:-}" ]; then
    echo "❌  No valid code-signing identity found." >&2
    echo "    Install a cert via Xcode → Preferences → Accounts, or:" >&2
    echo "      security create-keychain-certificate ..." >&2
    exit 1
fi
echo "✎  Signing as: $SIGN_IDENTITY"

# --- 1. Build ---
echo "⟳  Building (release)…"
cd "$PROJ_DIR"
swift build -c release 2>&1

BUILD_BIN="$PROJ_DIR/.build/release/$APP_NAME"
if [ ! -f "$BUILD_BIN" ]; then
    echo "❌  Binary not found at $BUILD_BIN" >&2; exit 1
fi

# --- 2. Stage bundle ---
echo "⟳  Assembling app bundle…"
rm -rf "$STAGED"
mkdir -p "$STAGED/Contents/MacOS" "$STAGED/Contents/Resources"

cp "$BUILD_BIN" "$STAGED/Contents/MacOS/$APP_NAME"
cp "$SOURCE_PLIST" "$STAGED/Contents/Info.plist"

if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$STAGED/Contents/Resources/AppIcon.icns"
else
    echo "⚠   AppIcon.icns not found at $ICON_SRC — bundle will lack an icon."
fi

# --- 3. Sign (consistent identity — ACL sticks) ---
echo "⟳  Signing…"
codesign --force --deep \
    --sign "$SIGN_IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --options runtime \
    "$STAGED"

echo "   Verifying signature…"
codesign --verify --deep --strict "$STAGED" 2>&1 \
    && echo "   ✓ Signature valid" \
    || { echo "❌  Codesign verification failed"; exit 1; }

# --- 4. Install ---
echo "⟳  Installing to /Applications…"
if [ -d "$INSTALLED" ]; then
    # Stop the running instance before replacing the binary
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
    rm -rf "$INSTALLED"
fi
cp -R "$STAGED" "$INSTALLED"

# --- 5. Launch / reload LaunchAgent ---
if [ -f "$LAUNCHAGENT" ]; then
    echo "⟳  Reloading LaunchAgent…"
    launchctl unload "$LAUNCHAGENT" 2>/dev/null || true
    sleep 0.3
    launchctl load "$LAUNCHAGENT"
else
    echo "⚠   LaunchAgent not found at $LAUNCHAGENT"
    echo "    Starting app directly…"
    open "$INSTALLED"
fi

echo ""
echo "✓  ClaudeUsage v1.1 installed."
echo ""
echo "  → If macOS shows a keychain dialog, click 'Always Allow'."
echo "    With a consistent signing identity, this grant now persists permanently."
echo "    (If you still see repeated prompts, export SIGN_IDENTITY='...' to pin the cert.)"
