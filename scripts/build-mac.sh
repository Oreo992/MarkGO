#!/usr/bin/env bash
# Build, ad-hoc sign, and package the MarkGo macOS app for distribution
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
#     xattr -dr com.apple.quarantine /Applications/MarkGo.app
#   See README.md for the full launch flow.

set -euo pipefail

CONFIGURATION="Release"
MAKE_ZIP=1
MAKE_DMG=1
MAKE_LOCAL_INSTALL=1

for arg in "$@"; do
  case "$arg" in
    --debug)     CONFIGURATION="Debug" ;;
    --skip-dmg)  MAKE_DMG=0 ;;
    --skip-zip)  MAKE_ZIP=0 ;;
    --skip-local-install) MAKE_LOCAL_INSTALL=0 ;;
    -h|--help)
      sed -n '1,40p' "$0"
      exit 0 ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 64 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/platforms/macos/MarkGo.xcodeproj"
SCHEME="MarkGo"
APP_NAME="MarkGo"
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
  --entitlements "$REPO_ROOT/platforms/macos/MarkGo/Resources/MarkdownReaderMac.entitlements" \
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
  RW_DMG_PATH="$EXPORT_DIR/$APP_NAME-$VERSION-mac-rw.dmg"
  STAGING="$EXPORT_DIR/dmg-staging"
  echo "▶︎ Creating dmg → $DMG_PATH"
  rm -rf "$STAGING"
  mkdir -p "$STAGING"
  cp -R "$APP_BUNDLE" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"

  mkdir -p "$STAGING/.background"
  python3 - <<PY 2>/dev/null || true
from pathlib import Path
try:
    from PIL import Image, ImageDraw, ImageFont
except Exception:
    raise SystemExit(0)

out = Path("$STAGING/.background/install-guide.png")
scale = 3
canvas = Image.new("RGB", (640 * scale, 400 * scale), (249, 247, 242))
draw = ImageDraw.Draw(canvas)

def font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size=size * scale, index=0)
        except Exception:
            continue
    return ImageFont.load_default()

title = font(30, True)
body = font(17)
small = font(14)
teal = (0, 173, 158)
ink = (52, 56, 58)
muted = (118, 124, 126)

# Keep the artwork simple. Finder will draw the real MarkGo and Applications
# icons over this background, so the background only supplies instructions and
# direction.
def xy(x, y):
    return (x * scale, y * scale)

draw.text(xy(44, 38), "安装 MarkGo", fill=ink, font=title)
draw.text(xy(44, 82), "拖动左边的 MarkGo 到右边的 Applications", fill=muted, font=body)
draw.text(xy(44, 340), "首次打开如被拦截：右键 MarkGo，选择“打开”。", fill=muted, font=small)

# Draw the arrow as solid geometry instead of a stroked line. A stroked line
# can leave a flat cap at the tip after Finder/downsampling.
draw.rounded_rectangle((*xy(238, 198), *xy(370, 210)), radius=3 * scale, fill=teal)
draw.polygon([xy(416, 204), xy(370, 176), xy(370, 232)], fill=teal)
draw.ellipse((*xy(308, 192), *xy(332, 216)), fill=(241, 101, 76))
canvas = canvas.resize((640, 400), Image.Resampling.LANCZOS)
canvas.save(out, optimize=True)
PY

  rm -f "$DMG_PATH" "$RW_DMG_PATH"
  hdiutil create \
    -fs HFS+ \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -format UDRW \
    -ov \
    "$RW_DMG_PATH" \
    > /dev/null

  MOUNT_DIR="$(mktemp -d /tmp/markgo-dmg.XXXXXX)"
  DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR" "$RW_DMG_PATH" | awk '/Apple_HFS/ { print $1; exit }')"
  if [[ -n "${DEVICE:-}" ]]; then
    if ! osascript <<APPLESCRIPT >/dev/null
tell application "Finder"
  set dmgFolder to POSIX file "$MOUNT_DIR" as alias
  tell folder dmgFolder
    open
    delay 0.4
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {140, 140, 780, 540}
    set viewOptions to icon view options of container window
    set icon size of viewOptions to 96
    set arrangement of viewOptions to not arranged
    set background picture of viewOptions to POSIX file "$MOUNT_DIR/.background/install-guide.png"
    set position of item "MarkGo.app" of container window to {160, 210}
    set position of item "Applications" of container window to {480, 210}
    update without registering applications
    close
  end tell
end tell
APPLESCRIPT
    then
      echo "  ⚠ Could not apply Finder DMG layout; using default icon view." >&2
    fi
    sync
    hdiutil detach "$DEVICE" >/dev/null || hdiutil detach "$DEVICE" -force >/dev/null || true
  fi
  rm -rf "$MOUNT_DIR"

  hdiutil convert "$RW_DMG_PATH" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" \
    > /dev/null
  rm -f "$RW_DMG_PATH"
  rm -rf "$STAGING"
  echo "  ✔ $(du -h "$DMG_PATH" | cut -f1) → $DMG_PATH"
fi

if [[ $MAKE_LOCAL_INSTALL -eq 1 ]]; then
  LOCAL_DIR="$DIST_DIR/MarkGo-local-install"
  LOCAL_ZIP="$DIST_DIR/$APP_NAME-$VERSION-local-install.zip"
  echo "▶︎ Creating local installer → $LOCAL_ZIP"
  rm -rf "$LOCAL_DIR" "$LOCAL_ZIP"
  mkdir -p "$LOCAL_DIR"
  cp -R "$APP_BUNDLE" "$LOCAL_DIR/$APP_NAME.app"
  cat > "$LOCAL_DIR/Install MarkGo.command" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="MarkGo"
SOURCE_APP="$PWD/$APP_NAME.app"
DEST_DIR="/Applications"
DEST_APP="$DEST_DIR/$APP_NAME.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Cannot find $SOURCE_APP"
  read -r -p "Press Return to close..."
  exit 1
fi

if [[ ! -w "$DEST_DIR" ]]; then
  DEST_DIR="$HOME/Applications"
  DEST_APP="$DEST_DIR/$APP_NAME.app"
  mkdir -p "$DEST_DIR"
fi

echo "Installing $APP_NAME to $DEST_APP"
rm -rf "$DEST_APP"
ditto "$SOURCE_APP" "$DEST_APP"
xattr -cr "$DEST_APP" 2>/dev/null || true
chmod -R u+rwX "$DEST_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST_APP" 2>/dev/null || true

echo
echo "$APP_NAME installed successfully."
echo "Opening $APP_NAME..."
open "$DEST_APP"
echo
read -r -p "Press Return to close..."
INSTALLER
  chmod +x "$LOCAL_DIR/Install MarkGo.command"
  cat > "$LOCAL_DIR/README.txt" <<INSTALLREADME
MarkGo local installer

1. Double-click "Install MarkGo.command".
2. If macOS asks for permission, choose Open.
3. The script copies MarkGo.app to /Applications when writable, otherwise to ~/Applications.
4. It removes quarantine/provenance attributes that can block local ad-hoc builds.

This build is ad-hoc signed and not notarized.
INSTALLREADME
  ditto -c -k --keepParent "$LOCAL_DIR" "$LOCAL_ZIP"
  echo "  ✔ $(du -h "$LOCAL_ZIP" | cut -f1) → $LOCAL_ZIP"
fi

echo
echo "✓ Done. Distribution artifacts in dist/:"
ls -lh "$DIST_DIR" 2>/dev/null | tail -n +2
echo
echo "Reminder: this app uses an ad-hoc signature, so on first launch users must"
echo "either right-click → Open, or run:"
echo "    xattr -dr com.apple.quarantine /Applications/$APP_NAME.app"
