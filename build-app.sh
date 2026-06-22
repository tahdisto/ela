#!/bin/bash
# Build ela.app — a self-contained menu-bar bundle with the model in Resources.
set -euo pipefail
cd "$(dirname "$0")"

APP="ela.app"
CONTENTS="$APP/Contents"

echo "→ swift build -c release"
swift build -c release >/dev/null

echo "→ assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/model"
cp .build/release/ela        "$CONTENTS/MacOS/ela"
cp app/Info.plist            "$CONTENTS/Info.plist"
cp data/model/lexicon.bin    "$CONTENTS/Resources/model/"
cp data/model/homographs.bin "$CONTENTS/Resources/model/"

echo "→ building Icon Composer .icon and compiling it (light/dark/tinted)"
rm -rf build/AppIcon.icon && mkdir -p build
swift scripts/make_icon.swift build/AppIcon.icon >/dev/null
xcrun actool build/AppIcon.icon --app-icon AppIcon \
  --compile "$CONTENTS/Resources" \
  --platform macosx --minimum-deployment-target 26.0 \
  --output-partial-info-plist build/icon-partial.plist >/dev/null 2>&1
# -> writes AppIcon.icns + Assets.car (Aqua + DarkAqua + Tintable) into Resources

# Sign with a real identity when available so the Accessibility grant survives
# rebuilds (designated requirement = identifier + cert, not the ad-hoc cdhash).
SIGN_ID=$(security find-identity -v -p codesigning | awk '/Developer ID Application/{print $2; exit}')
[ -z "$SIGN_ID" ] && SIGN_ID=$(security find-identity -v -p codesigning | awk '/Apple Development/{print $2; exit}')
if [ -n "$SIGN_ID" ]; then
  echo "→ codesign with stable identity ${SIGN_ID:0:10}…"
  codesign --force --sign "$SIGN_ID" --identifier eu.tahdisto.ela "$APP" >/dev/null
else
  echo "→ ad-hoc codesign (grant will not survive rebuilds)"
  codesign --force --sign - --identifier eu.tahdisto.ela "$APP" >/dev/null 2>&1
fi

echo "✓ built $APP"
du -sh "$APP"
