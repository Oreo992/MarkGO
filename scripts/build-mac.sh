#!/usr/bin/env bash
# Build, ad-hoc sign, and package the MarkLens macOS app for distribution
# outside the App Store. Produces both a .zip and a .dmg in dist/.
#
# Usage:
#   scripts/build-mac.sh                 # release build, both archive formats
#   scripts/build-mac.sh --debug         # debug build
#   scripts/build-mac.sh --skip-dmg      # skip dmg creation (zip only)
#   scripts/build-mac.sh --skip-zip      # skip zip creation (dmg only)
#
# Requirements:
#   - Xcode 15.0+ with command line tools
#   - macOS 13+ build host (for codesign + create-dmg fallback)
#
# Notes:
#   The signed app uses an ad-hoc signature (codesign --sign -). On first launch
#   end users must right-click → Open, or run:
#     xattr -dr com.apple.quarantine /Applications/MarkLens.app
#   See README.md for the full launch flow.

set -euo pipefail

CONFIGURATION="Release"
MAKE_ZIP=1
MAKE_DMG=1

for arg in "$@"; do
  case "$arg" in
    --debug)     CONFIGURATION="Debug" ;;
    --skip-dmg)  MAKE_DMG=0 ;;
    --skip-zip)  MAKE_ZIP=0 ;;
    -h|--help)
      sed -n '1,40p' "$0"
      exit 0 ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 64 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/MarkdownReaderMac.xcodeproj"
SCHEME="MarkLens"
APP_NAME="MarkLens"
DERIVED_DATA="$REPO_ROOT/.build/derivedData"
EXPORT_DIR="$REPO_ROOT/.build/export"
DIST_DIR="$REPO_ROOT/dist"

mkdir -p "$DERIVED_DATA" "$EXPORT_DIR" "$DIST_DIR"

echo "▶︎ Building $APP_NAME ($CONFIGURATION) for arm64 + x86_64 (Universal)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build \
  | tail -20

BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

if [[ ! -d "$BUILT_APP" ]]; then
  echo "✗ Could not find built app at $BUILT_APP" >&2
  exit 1
fi

# Copy to a clean export location
rm -rf "$EXPORT_DIR/$APP_NAME.app"
cp -R "$BUILT_APP" "$EXPORT_DIR/$APP_NAME.app"
APP_BUNDLE="$EXPORT_DIR/$APP_NAME.app"

echo "▶︎ Re-signing bundle ad-hoc…"
codesign --remove-signature "$APP_BUNDLE" 2>/dev/null || true
codesign \
  --force \
  --deep \
  --sign - \
  --entitlements "$REPO_ROOT/MarkdownReaderMac/Resources/MarkdownReaderMac.entitlements" \
  --options runtime \
  "$APP_BUNDLE" \
  || codesign --force --deep --sign - "$APP_BUNDLE"

echo "▶︎ Verifying signature…"
codesign --display --verbose=2 "$APP_BUNDLE" 2>&1 | head -5
spctl --assess --type execute --verbose "$APP_BUNDLE" 2>&1 || true

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || echo "dev")

if [[ $MAKE_ZIP -eq 1 ]]; then
  ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-mac.zip"
  echo "▶︎ Creating zip → $ZIP_PATH"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
  echo "  ✔ $(du -h "$ZIP_PATH" | cut -f1) → $ZIP_PATH"
fi

if [[ $MAKE_DMG -eq 1 ]]; then
  DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-mac.dmg"
  STAGING="$EXPORT_DIR/dmg-staging"
  echo "▶︎ Creating dmg → $DMG_PATH"
  rm -rf "$STAGING"
  mkdir -p "$STAGING"
  cp -R "$APP_BUNDLE" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  rm -f "$DMG_PATH"
  hdiutil create \
    -fs HFS+ \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$DMG_PATH" \
    > /dev/null
  rm -rf "$STAGING"
  echo "  ✔ $(du -h "$DMG_PATH" | cut -f1) → $DMG_PATH"
fi

echo
echo "✓ Done. Distribution artifacts in dist/:"
ls -lh "$DIST_DIR" 2>/dev/null | tail -n +2
echo
echo "Reminder: this app uses an ad-hoc signature, so on first launch users must"
echo "either right-click → Open, or run:"
echo "    xattr -dr com.apple.quarantine /Applications/$APP_NAME.app"
