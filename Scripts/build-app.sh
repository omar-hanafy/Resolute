#!/usr/bin/env bash
# Builds dist/Resolute.app and dist/resolute as universal binaries, signed ad hoc.
#   UNIVERSAL=0 Scripts/build-app.sh    # this Mac's architecture only (faster)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/ResoluteKit/Version.swift)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
ARCHS=(--arch arm64 --arch x86_64)
[[ "${UNIVERSAL:-1}" == "0" ]] && ARCHS=()

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

APP="dist/Resolute.app"
rm -rf "$APP" dist/resolute
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/ResoluteApp" "$APP/Contents/MacOS/Resolute"
cp "$BIN/resolute" "$APP/Contents/Helpers/resolute"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# SwiftPM's default build system records the deployment target as the SDK version, so
# AppKit would treat the app as built for macOS 14. Record the SDK actually used.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
for binary in "$APP/Contents/MacOS/Resolute" "$APP/Contents/Helpers/resolute"; do
  MIN_OS="$(vtool -show-build "$binary" | awk '/minos/ { print $2; exit }')"
  vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace -output "$binary.stamped" "$binary"
  mv "$binary.stamped" "$binary"
done

codesign --force --sign - --identifier com.omarhanafy.Resolute.cli "$APP/Contents/Helpers/resolute"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
cp "$APP/Contents/Helpers/resolute" dist/resolute

echo "Built $APP and dist/resolute (version $VERSION, build $BUILD)"
