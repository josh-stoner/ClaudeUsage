#!/usr/bin/env bash
# build.sh — deterministic build, sign, and install for ClaudeUsage
# Usage: ./build.sh [--identity "Your Cert Name"] [--notarize]
#
# Signs with the SAME identity on every run so macOS keychain ACL
# "Always Allow" grants persist across rebuilds.
#
# --notarize  Submit to Apple notarization after signing and staple the ticket.
#             Requires: xcrun notarytool store-credentials "claudeusage-notary"
#                       (one-time setup — see NOTARIZE.md or run without flag for local builds)
set -euo pipefail

NOTARIZE=false

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity)
            SIGN_IDENTITY="${2:?'--identity requires a value'}"
            shift 2
            ;;
        --notarize)
            NOTARIZE=true
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2; exit 1
            ;;
    esac
done

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeUsage"
BUNDLE_ID="com.stoneros.claude-usage"
STAGED="$PROJ_DIR/.staged/$APP_NAME.app"
INSTALLED="/Applications/$APP_NAME.app"
LAUNCHAGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
LAUNCHAGENT_SRC="$PROJ_DIR/LaunchAgent/$BUNDLE_ID.plist"
SOURCE_PLIST="$PROJ_DIR/$APP_NAME/Info.plist"
ICON_SRC="$PROJ_DIR/icon/AppIcon.icns"

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
    --requirements "$PROJ_DIR/devid.req" \
    --options runtime \
    "$STAGED"

echo "   Verifying signature…"
codesign --verify --deep --strict "$STAGED" 2>&1 \
    && echo "   ✓ Signature valid" \
    || { echo "❌  Codesign verification failed"; exit 1; }

# --- 3b. Notarize (opt-in) ---
if [ "$NOTARIZE" = true ]; then
    echo "⟳  Notarizing…"
    ZIP="$PROJ_DIR/.staged/${APP_NAME}.zip"
    ditto -c -k --keepParent "$STAGED" "$ZIP"
    xcrun notarytool submit "$ZIP" \
        --keychain-profile "claudeusage-notary" \
        --wait
    echo "⟳  Stapling notarization ticket…"
    xcrun stapler staple "$STAGED"
    echo "   ✓ Notarization complete"
    rm -f "$ZIP"
fi

# --- 4. Install ---
echo "⟳  Installing to /Applications…"
if [ -d "$INSTALLED" ]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
    rm -rf "$INSTALLED"
fi
cp -R "$STAGED" "$INSTALLED"

# --- 5. Install versioned LaunchAgent from repo ---
if [ -f "$LAUNCHAGENT_SRC" ]; then
    echo "⟳  Installing LaunchAgent…"
    # Unload existing agent (ignore error if not loaded)
    launchctl unload "$LAUNCHAGENT" 2>/dev/null || true
    cp "$LAUNCHAGENT_SRC" "$LAUNCHAGENT"
    sleep 0.3
    launchctl load "$LAUNCHAGENT"
    echo "   ✓ LaunchAgent loaded"
else
    echo "⚠   No versioned plist at $LAUNCHAGENT_SRC"
    if [ -f "$LAUNCHAGENT" ]; then
        echo "⟳  Reloading existing LaunchAgent…"
        launchctl unload "$LAUNCHAGENT" 2>/dev/null || true
        sleep 0.3
        launchctl load "$LAUNCHAGENT"
    else
        echo "    Starting app directly…"
        open "$INSTALLED"
    fi
fi

echo ""
if [ "$NOTARIZE" = true ]; then
    echo "✓  ClaudeUsage installed and notarized."
    echo "   Verify: spctl -a -vvv -t install \"$INSTALLED\""
else
    echo "✓  ClaudeUsage v1.2 installed."
fi
echo ""
echo "  → If macOS shows a keychain dialog, click 'Always Allow'."
echo "    With a consistent signing identity, this grant now persists permanently."
