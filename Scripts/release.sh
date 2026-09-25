#!/usr/bin/env bash
# Builds a universal Resolute.app and packages it for release:
#   dist/Resolute-<version>.zip, dist/Resolute-<version>.dmg, dist/SHA256SUMS
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=my-profile Scripts/release.sh
# SIGN_IDENTITY is passed through to build-app.sh (default ad hoc; see there). With
# NOTARY_PROFILE set to a keychain profile already created with
# `xcrun notarytool store-credentials`, the zip and the dmg are each submitted to Apple
# and stapled; this requires SIGN_IDENTITY to be a Developer ID Application identity.
# Without NOTARY_PROFILE the build is signed but not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:--}"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  case "$SIGN_IDENTITY" in
    "Developer ID Application:"*) ;;
    *)
      echo "NOTARY_PROFILE needs SIGN_IDENTITY to be a Developer ID Application identity, not '$SIGN_IDENTITY'." >&2
      exit 1
      ;;
  esac
fi

UNIVERSAL=1 SIGN_IDENTITY="$SIGN_IDENTITY" Scripts/build-app.sh

VERSION="$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/ResoluteKit/Version.swift)"
APP="dist/Resolute.app"
ZIP_NAME="Resolute-$VERSION.zip"
DMG_NAME="Resolute-$VERSION.dmg"
ZIP="dist/$ZIP_NAME"
DMG="dist/$DMG_NAME"

STAGING=""
cleanup() { [[ -n "$STAGING" ]] && rm -rf "$STAGING"; }
trap cleanup EXIT

make_zip() {
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
}

make_dmg() {
  rm -f "$DMG"
  STAGING="$(mktemp -d)"
  ditto "$APP" "$STAGING/Resolute.app"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "Resolute $VERSION" -srcfolder "$STAGING" -format UDZO -ov "$DMG"
}

make_zip

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Notarizing $ZIP_NAME…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  make_zip # the staple changed the app, so the zip must be remade

  make_dmg
  echo "Notarizing $DMG_NAME…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
else
  make_dmg
  echo "Not notarized: Gatekeeper will block a downloaded copy until NOTARY_PROFILE is set."
fi

(cd dist && shasum -a 256 "$ZIP_NAME" "$DMG_NAME" > SHA256SUMS)

echo "Built $ZIP, $DMG and dist/SHA256SUMS"
echo "Release command:"
echo "  gh release create v$VERSION $ZIP $DMG dist/SHA256SUMS --title \"Resolute $VERSION\" --notes-file CHANGELOG.md"
