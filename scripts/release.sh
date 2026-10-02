#!/usr/bin/env bash
#
# release.sh — Build, sign, notarize, and package Squeegee as a DMG.
#
# Usage:
#   make release
#   # or directly:
#   ./scripts/release.sh
#
# Required environment:
#   NOTARYTOOL_PROFILE  — keychain profile name for notarytool (default: notarytool-password-scosman)
#
# Prerequisites:
#   - Xcode with "Developer ID Application" signing identity
#   - XcodeGen (brew install xcodegen)
#   - A notarytool keychain profile (see: xcrun notarytool store-credentials)
#   - The Xcode project generated (make generate)
#

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/App"
PROJECT_YML="$APP_DIR/project.yml"
PROJECT_FILE="$APP_DIR/Squeegee.xcodeproj"
SCHEME="Squeegee"
BUNDLE_ID="net.scosman.squeegee"
TEAM_ID="B5L5M4B62J"
SIGN_IDENTITY="Developer ID Application"

NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-notarytool-password-scosman}"

BUILD_DIR="$REPO_ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/Squeegee.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_PLIST="$BUILD_DIR/export-options.plist"

# ── Helpers ────────────────────────────────────────────────────────────────────

log()   { printf '==> %s\n' "$*"; }
error() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_tool() {
    command -v "$1" >/dev/null 2>&1 || error "'$1' not found. Install it before running this script."
}

# ── Preflight checks ──────────────────────────────────────────────────────────

log "Preflight checks"

require_tool xcodebuild
require_tool xcrun
require_tool hdiutil
require_tool codesign

# Verify the signing identity exists
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    error "Signing identity '$SIGN_IDENTITY' not found in keychain. Install your Developer ID certificate."
fi

# Verify notarytool profile exists
if ! xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE" >/dev/null 2>&1; then
    error "Notarytool keychain profile '$NOTARYTOOL_PROFILE' not found. Create it with: xcrun notarytool store-credentials \"$NOTARYTOOL_PROFILE\" --apple-id <email> --team-id $TEAM_ID --password <app-specific-password>"
fi

# ── Read version from project.yml ─────────────────────────────────────────────

if [[ ! -f "$PROJECT_YML" ]]; then
    error "project.yml not found at $PROJECT_YML"
fi

VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_YML" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '[:space:]')
if [[ -z "$VERSION" ]]; then
    error "Could not read MARKETING_VERSION from $PROJECT_YML"
fi

log "Version: $VERSION"

# ── Clean + prepare ───────────────────────────────────────────────────────────

log "Preparing build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Generate Xcode project ────────────────────────────────────────────────────

log "Generating Xcode project"
(cd "$APP_DIR" && xcodegen generate)

if [[ ! -d "$PROJECT_FILE" ]]; then
    error "Xcode project not found at $PROJECT_FILE after generation"
fi

# ── Archive ────────────────────────────────────────────────────────────────────

log "Archiving (Release, Developer ID)"
xcodebuild archive \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=macOS' \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES

if [[ ! -d "$ARCHIVE_PATH" ]]; then
    error "Archive failed — no archive at $ARCHIVE_PATH"
fi

# ── Zip dSYM ───────────────────────────────────────────────────────────────────

DSYM_PATH="$ARCHIVE_PATH/dSYMs/Squeegee.app.dSYM"
DSYM_ZIP="$BUILD_DIR/Squeegee-${VERSION}.dSYM.zip"

if [[ -d "$DSYM_PATH" ]]; then
    log "Zipping dSYM"
    ditto -c -k --keepParent "$DSYM_PATH" "$DSYM_ZIP"
    log "dSYM archive: $DSYM_ZIP"
else
    log "WARNING: dSYM not found at $DSYM_PATH — skipping dSYM zip"
fi

# ── Export archive ─────────────────────────────────────────────────────────────

log "Exporting archive"

cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>${SIGN_IDENTITY}</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -exportPath "$EXPORT_DIR"

APP_PATH="$EXPORT_DIR/Squeegee.app"
if [[ ! -d "$APP_PATH" ]]; then
    error "Export failed — no app at $APP_PATH"
fi

# ── Notarize the app ──────────────────────────────────────────────────────────

log "Notarizing app"

# Create a zip for notarization
APP_ZIP="$BUILD_DIR/Squeegee-app.zip"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

xcrun notarytool submit "$APP_ZIP" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

log "Stapling app"
xcrun stapler staple "$APP_PATH"

# ── Create DMG ─────────────────────────────────────────────────────────────────

DMG_NAME="Squeegee-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
DMG_STAGING="$BUILD_DIR/dmg-staging"

log "Creating DMG"

mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "Squeegee" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

# ── Sign the DMG ──────────────────────────────────────────────────────────────

log "Signing DMG"
codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"

# ── Notarize the DMG ──────────────────────────────────────────────────────────

log "Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

log "Stapling DMG"
xcrun stapler staple "$DMG_PATH"

# ── Done ───────────────────────────────────────────────────────────────────────

log "Release complete: $DMG_PATH"
