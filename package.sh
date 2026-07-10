#!/usr/bin/env bash
# package.sh — build a distributable DMG from the signed .app bundle
# Usage: ./package.sh [--version 1.2]
#
# Prerequisites: run ./build.sh (with optional --notarize) first.
# Output: ClaudeUsage-<version>.dmg in the repo root.
set -euo pipefail

VERSION="1.2"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2:?'--version requires a value'}"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2; exit 1
            ;;
    esac
done

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeUsage"
INSTALLED="/Applications/$APP_NAME.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$PROJ_DIR/$DMG_NAME"
STAGING_DIR="$PROJ_DIR/.dmg-staging"

if [ ! -d "$INSTALLED" ]; then
    echo "❌  $INSTALLED not found — run ./build.sh first." >&2; exit 1
fi

echo "⟳  Assembling DMG staging directory…"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$INSTALLED" "$STAGING_DIR/"
# Symlink to /Applications so users can drag-install
ln -s /Applications "$STAGING_DIR/Applications"

echo "⟳  Creating DMG…"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo ""
echo "✓  $DMG_NAME created at: $DMG_PATH"
echo "   Share or attach to a GitHub release."
if xcrun stapler validate "$INSTALLED" &>/dev/null; then
    echo "   Notarization ticket is stapled — DMG is Gatekeeper-ready."
else
    echo "⚠   App is not notarized. Run ./build.sh --notarize first for public distribution."
fi
