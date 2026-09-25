#!/usr/bin/env bash
# Installs Resolute.app and links the resolute command.
#   RESOLUTE_APP_DIR=~/Applications RESOLUTE_BIN_DIR=~/.local/bin Scripts/install.sh
set -euo pipefail
# shellcheck source=Scripts/lib.sh
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

APP_DIR="${RESOLUTE_APP_DIR:-/Applications}"
BIN_DIR="${RESOLUTE_BIN_DIR:-/usr/local/bin}"
BUNDLE_ID="${RESOLUTE_BUNDLE_ID:-com.omarhanafy.Resolute}"

[[ -d dist/Resolute.app ]] || Scripts/build-app.sh

# The old process may still be exiting, or may be asking about unsaved custom
# resolutions; either way, swapping the bundle under it would be unsafe.
if ! quit_and_wait; then
  echo "Resolute is still running (it may be asking about unsaved custom resolutions)." >&2
  echo "Quit it and run this script again." >&2
  exit 1
fi

rm -rf "$APP_DIR/Resolute.app"
ditto dist/Resolute.app "$APP_DIR/Resolute.app"
echo "Installed $APP_DIR/Resolute.app"

CLI="$APP_DIR/Resolute.app/Contents/Helpers/resolute"
if [[ -d "$BIN_DIR" && -w "$BIN_DIR" ]]; then
  ln -sf "$CLI" "$BIN_DIR/resolute"
  echo "Linked $BIN_DIR/resolute"
else
  echo "To use the command-line tool, run: sudo mkdir -p \"$BIN_DIR\" && sudo ln -sf \"$CLI\" \"$BIN_DIR/resolute\""
fi

open "$APP_DIR/Resolute.app"
