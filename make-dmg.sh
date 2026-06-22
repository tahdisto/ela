#!/bin/bash
# Build a drag-to-install ela.dmg (app + arrow + Applications symlink).
# Requires ela.app (runs build-app.sh if missing). Finder styling is best-effort.
set -euo pipefail
cd "$(dirname "$0")"

APP="ela.app"
VOL="ela"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
OUT="ela-$VER.dmg"
RW="build/ela-rw.dmg"
STAGE="build/dmg"
MNT="/Volumes/$VOL"

[ -d "$APP" ] || ./build-app.sh
mkdir -p build
echo "→ rendering DMG background"
swift scripts/dmg_background.swift build/dmg-bg.png >/dev/null

echo "→ staging contents"
rm -rf "$STAGE"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/ela.app"
cp build/dmg-bg.png "$STAGE/.background/bg.png"
ln -s /Applications "$STAGE/Applications"

echo "→ creating writable image"
rm -f "$RW" "$OUT"
hdiutil detach "$MNT" >/dev/null 2>&1 || true
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" >/dev/null

echo "→ laying out Finder window"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep -E '^/dev/' | head -1 | awk '{print $1}')
sleep 1
osascript <<OSA 2>/dev/null || echo "  (Finder styling skipped — DMG still works)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 540}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 112
    set background picture of vo to file ".background:bg.png"
    set position of item "ela.app" of container window to {150, 205}
    set position of item "Applications" of container window to {450, 205}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
sync
hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$MNT" >/dev/null 2>&1 || true

echo "→ compressing"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$RW"

# sign the dmg with the same identity as the app, if available
SIGN_ID=$(security find-identity -v -p codesigning | awk '/Developer ID Application/{print $2; exit}')
[ -z "$SIGN_ID" ] && SIGN_ID=$(security find-identity -v -p codesigning | awk '/Apple Development/{print $2; exit}')
[ -n "$SIGN_ID" ] && codesign --force --sign "$SIGN_ID" "$OUT" >/dev/null 2>&1 || true

echo "✓ built $OUT"
du -sh "$OUT"
