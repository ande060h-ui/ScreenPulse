#!/bin/zsh
# Builds ScreenPulse.app and the capsled command-line tool.
#
#   ./app/build.sh             development build (reads .env and knowledge/ from this checkout)
#   ./app/build.sh --release   self-contained build with no link to the source folder
#
# Environment:
#   SIGN_IDENTITY   code signing identity (default "-" = ad-hoc). Use your
#                   "Developer ID Application: …" identity for distribution.
#   ARCHS           architectures to build (default "arm64 x86_64")
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/ScreenPulse.app"
BUNDLE_ID="com.screenpulse.ScreenPulse"
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' package.json | head -1)"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_MACOS="13.0"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ARCHS=(${=ARCHS:-arm64 x86_64})

RELEASE=0
[[ "$1" == "--release" ]] && RELEASE=1

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Compile one binary per architecture, then merge them into a universal binary.
build_universal() { # <output> <frameworks…> -- <sources…>
  local out="$1"; shift
  local slices=()
  for arch in $ARCHS; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos$MIN_MACOS" "$@" -o "$TMP/$(basename "$out")-$arch"
    slices+=("$TMP/$(basename "$out")-$arch")
  done
  lipo -create "${slices[@]}" -output "$out"
}

build_universal "$APP/Contents/MacOS/ScreenPulse" \
  app/Sources/Core/*.swift app/Sources/Shared/*.swift app/Sources/ScreenPulse/*.swift \
  -framework AppKit -framework Carbon -framework IOKit -framework SwiftUI \
  -framework Security -framework ServiceManagement

# The stand-alone capsled CLI (keyboard signals from Terminal, and `capsled probe`)
build_universal "$ROOT/build/capsled" \
  app/Sources/Core/*.swift app/Sources/Shared/*.swift app/Sources/capsled/*.swift \
  -framework IOKit -framework CoreGraphics

# Icon: draw a 1024 px image and turn it into .icns
swiftc -O -swift-version 5 app/Tools/make-icon.swift -o "$TMP/make-icon" -framework AppKit
"$TMP/make-icon" "$TMP/icon.png"
mkdir "$TMP/AppIcon.iconset"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

PROJECT_DIR_KEY=""
if [[ $RELEASE -eq 0 ]]; then
  PROJECT_DIR_KEY="  <key>SPProjectDir</key><string>$ROOT</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ScreenPulse</string>
  <key>CFBundleDisplayName</key><string>ScreenPulse</string>
  <key>CFBundleExecutable</key><string>ScreenPulse</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 ScreenPulse. All rights reserved.</string>
  <key>NSInputMonitoringUsageDescription</key><string>ScreenPulse controls the Caps Lock light to signal answers.</string>
$PROJECT_DIR_KEY
</dict>
</plist>
PLIST

# A fixed designated requirement keeps macOS permissions across ad-hoc rebuilds.
# With a Developer ID identity the hardened runtime is enabled for notarization.
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - -r="designated => identifier \"$BUNDLE_ID\"" "$APP"
  codesign --force --sign - "$ROOT/build/capsled"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$ROOT/build/capsled"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

echo "Done: $APP"
echo "      $ROOT/build/capsled"
