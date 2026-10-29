#!/usr/bin/env bash
# Renders the design gallery from a copy of the debug app stamped with the SDK it was built
# with, as build-app.sh stamps the shipped app: unstamped, AppKit draws controls and window
# backgrounds the way it does for apps built for macOS 14.
#
# Usage: Scripts/render-gallery.sh <folder> [--only <id-prefix>,…] [--appearance light|dark|both]
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -lt 1 || "$1" == -* ]]; then
  echo "usage: Scripts/render-gallery.sh <folder> [--only <id-prefix>,…] [--appearance light|dark|both]" >&2
  exit 64
fi

swift build --product ResoluteApp
BIN_PATH="$(swift build --show-bin-path)"
binary="$BIN_PATH/ResoluteApp"
stamped="$BIN_PATH/ResoluteApp-gallery"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
MIN_OS="$(vtool -show-build "$binary" | awk '/minos/ { print $2; exit }')"
vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace -output "$stamped" "$binary"
codesign --force --sign - "$stamped"
exec "$stamped" --render-gallery "$@"
