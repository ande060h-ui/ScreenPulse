#!/bin/zsh
# Builds build/ScreenPulse.dmg: the installer disk image with the "drag to Applications" window.
#
#   ./scripts/make-dmg.sh                 unsigned image (opens after "Open Anyway" on other Macs)
#
# To sign and notarize (needs an Apple Developer Program membership), set:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD   (an app-specific password)
#   or NOTARY_PROFILE="name"                            (a profile made with xcrun notarytool store-credentials)
#
# SKIP_BUILD=1 reuses an existing build/ScreenPulse.app.
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/ScreenPulse.app"
DMG="$ROOT/build/ScreenPulse.dmg"
VOLUME="ScreenPulse"
WORK="$ROOT/build/dmg"
if [[ "$PREVIEW" == "1" ]]; then   # test build, see app/build.sh
  APP="$ROOT/build/ScreenPulse Preview.app"
  DMG="$ROOT/build/ScreenPulse-Preview.dmg"
  VOLUME="ScreenPulse Preview"
fi

[[ "$SKIP_BUILD" == "1" && -d "$APP" ]] || ./app/build.sh --release

rm -rf "$WORK" "$DMG"
mkdir -p "$WORK"

# Window background: one 660×400 PNG, the same size as the window.
# A combined 1x/2x TIFF was tried first, but Finder on a real MacBook showed the 2x image at full size
# (arrow in the corner, text twice as big), so only the 1x image is used.
swiftc -O -swift-version 5 app/Tools/make-dmg-background.swift -o "$WORK/make-bg" -framework AppKit
# The 2x file must not be named background@2x.png: dmgbuild would merge it back into a TIFF.
"$WORK/make-bg" "$WORK/background.png" "$WORK/unused-retina.png"
rm -f "$WORK/unused-retina.png"

# dmgbuild writes the window layout directly, so it also works on a build server without a screen
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet "dmgbuild>=1.6"
"$WORK/venv/bin/dmgbuild" -s app/dmg/settings.py \
  -D app="$APP" -D bg="$WORK/background.png" -D icon="$APP/Contents/Resources/AppIcon.icns" \
  "$VOLUME" "$DMG"

if [[ -n "$SIGN_IDENTITY" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  elif [[ -n "$NOTARY_APPLE_ID" && -n "$NOTARY_TEAM_ID" && -n "$NOTARY_PASSWORD" ]]; then
    xcrun notarytool submit "$DMG" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait
    xcrun stapler staple "$DMG"
  else
    echo "Signed but NOT notarized: set NOTARY_* or NOTARY_PROFILE."
  fi
else
  echo "Unsigned disk image: other Macs will need System Settings → Privacy & Security → Open Anyway."
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Done: $DMG"
