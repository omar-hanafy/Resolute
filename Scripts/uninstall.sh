#!/usr/bin/env bash
# Removes Resolute.app, its command-line link and its preferences.
# Override files and their backups are left in place (see README.md).
set -euo pipefail
# shellcheck source=Scripts/lib.sh
source "$(dirname "$0")/lib.sh"

APP_DIR="${RESOLUTE_APP_DIR:-/Applications}"
BIN_DIR="${RESOLUTE_BIN_DIR:-/usr/local/bin}"
BUNDLE_ID="com.omarhanafy.Resolute"
APP_PATH="$APP_DIR/Resolute.app"

# Turn off Launch at Login before the app binary is gone. Older builds without this
# diagnostic flag are ignored, not treated as a failure.
if [[ -d "$APP_PATH" ]]; then
  "$APP_PATH/Contents/MacOS/Resolute" --unregister-login-item >/dev/null 2>&1 || true
fi

# The old process may still be exiting, or may be asking about unsaved custom
# resolutions; either way, deleting the bundle under it would be unsafe.
if ! quit_and_wait; then
  echo "Resolute is still running (it may be asking about unsaved custom resolutions)." >&2
  echo "Quit it and run this script again." >&2
  exit 1
fi

rm -rf "$APP_PATH"
if [[ -L "$BIN_DIR/resolute" && "$(readlink "$BIN_DIR/resolute")" == *"Resolute.app/Contents/Helpers/resolute" ]]; then
  rm -f "$BIN_DIR/resolute" 2>/dev/null || echo "Remove the command-line link with: sudo rm \"$BIN_DIR/resolute\""
fi
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "Removed Resolute."
echo "Custom resolution overrides in /Library/Displays and backups in /Library/Application Support/Resolute are untouched."
