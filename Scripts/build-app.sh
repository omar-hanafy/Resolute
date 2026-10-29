#!/usr/bin/env bash
# Builds dist/Resolute.app and dist/resolute for Apple silicon.
#   UNIVERSAL=1 Scripts/build-app.sh    # optional Apple silicon + Intel compatibility
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" Scripts/build-app.sh
# SIGN_IDENTITY defaults to "-" (ad hoc, local use only). A real identity also turns on
# the hardened runtime and, only for a "Developer ID Application" identity, an Apple
# timestamp (other identities' signatures can't be timestamped by Apple's server).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/ResoluteKit/Version.swift)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
ARCHS=(--arch arm64)
case "${UNIVERSAL:-0}" in
  0) ;;
  1) ARCHS+=(--arch x86_64) ;;
  *) echo "UNIVERSAL must be 0 (Apple silicon) or 1 (universal)." >&2; exit 1 ;;
esac
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

APP="dist/Resolute.app"
rm -rf "$APP" dist/resolute
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/ResoluteApp" "$APP/Contents/MacOS/Resolute"
cp "$BIN/resolute" "$APP/Contents/Helpers/resolute"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
mkdir -p "$APP/Contents/Resources/ThirdPartyLicenses"
cp .build/checkouts/swift-argument-parser/LICENSE.txt "$APP/Contents/Resources/ThirdPartyLicenses/swift-argument-parser.txt"
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

# App Intents (Shortcuts, Siri, Spotlight): macOS finds them only through
# Contents/Resources/Metadata.appintents, which Xcode writes with appintentsmetadataprocessor
# from the constant values the compiler extracts. SwiftPM doesn't ask for those, and an
# -Xswiftc flag would reach every module, so a second compile of the ResoluteApp module alone
# extracts them, into a folder made new on every run so nothing stale is read.
META="$(mktemp -d "${TMPDIR:-/tmp}/resolute-appintents.XXXXXX")"
trap 'rm -rf "$META"' EXIT
MODULES="$(find "$BIN" -maxdepth 2 -name ResoluteKit.swiftmodule -print -quit)"
if [[ -z "$MODULES" ]]; then
  echo "ResoluteKit.swiftmodule is not under $BIN, so App Intents can't be extracted." >&2
  exit 1
fi
MODULES="$(dirname "$MODULES")"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
DEPLOYMENT_TARGET="$(vtool -show-build "$APP/Contents/MacOS/Resolute" | awk '/minos/ { print $2; exit }')"
TRIPLE="arm64-apple-macos$DEPLOYMENT_TARGET"
find "$PWD/Sources/ResoluteApp" -name '*.swift' | sort > "$META/sources.txt"
# Every protocol any supported Xcode extracts App Intents types by; a name a compiler doesn't
# know matches nothing.
cat > "$META/protocols.json" <<'JSON'
["AnyResolverProviding","AppEntity","AppEnum","AppIntent","AppIntentsPackage","AppShortcutProviding","AppShortcutsProvider","DynamicOptionsProvider","EntityQuery","IntentValueQuery","TransientEntity","_IntentValueRepresentable"]
JSON
xcrun swiftc -wmo -c -o "$META/ResoluteApp.o" -module-name ResoluteApp -swift-version 6 \
  -target "$TRIPLE" -sdk "$SDK_PATH" -I "$MODULES" \
  -emit-const-values-path "$META/ResoluteApp.swiftconstvalues" \
  -Xfrontend -const-gather-protocols-file -Xfrontend "$META/protocols.json" \
  "@$META/sources.txt"
echo "$META/ResoluteApp.swiftconstvalues" > "$META/constvals.txt"

# Older processors lack some options, so only those this one lists in --help are passed.
PROCESSOR_HELP="$(xcrun appintentsmetadataprocessor --help 2>&1 || true)"
supports() { grep -qE -e "(^|[[:space:],])$1([[:space:],]|$)" <<<"$PROCESSOR_HELP"; }
PROCESSOR_FLAGS=()
for option in --compile-time-extraction --deployment-aware-processing --no-app-shortcuts-localization --force; do
  if supports "$option"; then PROCESSOR_FLAGS+=("$option"); fi
done
if supports --bundle-identifier; then
  PROCESSOR_FLAGS+=(--bundle-identifier "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")")
fi
TOOLCHAIN_DIR="$(cd "$(dirname "$(xcrun --find swiftc)")/../.." && pwd)"
XCODE_BUILD="$(xcodebuild -version | awk '/Build version/ { print $3 }')"
ACTIONS_DATA="$APP/Contents/Resources/Metadata.appintents/extract.actionsdata"
process_app_intents() {
  # Its exit status says little, so what counts is the file macOS reads.
  xcrun appintentsmetadataprocessor --output "$APP/Contents/Resources" --toolchain-dir "$TOOLCHAIN_DIR" \
    --module-name ResoluteApp --sdk-root "$SDK_PATH" --xcode-version "$XCODE_BUILD" --platform-family macOS \
    --deployment-target "$DEPLOYMENT_TARGET" --target-triple "$TRIPLE" --source-file-list "$META/sources.txt" \
    --swift-const-vals-list "$META/constvals.txt" "$@" || true
}
process_app_intents ${PROCESSOR_FLAGS[@]+"${PROCESSOR_FLAGS[@]}"}
if [[ ! -s "$ACTIONS_DATA" ]]; then
  # A processor that hides the options Xcode passes may still need them.
  echo "No App Intents metadata yet; trying again with the options Xcode passes." >&2
  process_app_intents ${PROCESSOR_FLAGS[@]+"${PROCESSOR_FLAGS[@]}"} --compile-time-extraction \
    --binary-file "$APP/Contents/MacOS/Resolute"
fi
if [[ ! -s "$ACTIONS_DATA" ]]; then
  echo "appintentsmetadataprocessor wrote no $ACTIONS_DATA, so Shortcuts would find no actions." >&2
  exit 1
fi

# Ad hoc signing (the default) never leaves this Mac, so it gets neither the hardened
# runtime nor a timestamp. Neither binary needs entitlements: the app calls SkyLight via
# dlsym on system frameworks and runs /usr/bin/osascript as a subprocess.
CODESIGN_FLAGS=()
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  CODESIGN_FLAGS+=(--options runtime)
  case "$SIGN_IDENTITY" in
    "Developer ID Application:"*) CODESIGN_FLAGS+=(--timestamp) ;;
    *) CODESIGN_FLAGS+=(--timestamp=none) ;;
  esac
fi

codesign --force --sign "$SIGN_IDENTITY" ${CODESIGN_FLAGS[@]+"${CODESIGN_FLAGS[@]}"} \
  --identifier com.omarhanafy.Resolute.cli "$APP/Contents/Helpers/resolute"
codesign --force --sign "$SIGN_IDENTITY" ${CODESIGN_FLAGS[@]+"${CODESIGN_FLAGS[@]}"} "$APP"
codesign --verify --strict "$APP/Contents/Helpers/resolute"
codesign --verify --strict "$APP"
cp "$APP/Contents/Helpers/resolute" dist/resolute

echo "Built $APP and dist/resolute (version $VERSION, build $BUILD), signed with: $SIGN_IDENTITY"
