#!/usr/bin/env bash
# Removes Resolute.app, its command-line link and its preferences.
# Override files and their backups are left in place (see README.md).
set -euo pipefail

APP_DIR="${RESOLUTE_APP_DIR:-/Applications}"
BIN_DIR="${RESOLUTE_BIN_DIR:-/usr/local/bin}"
BUNDLE_ID="com.omarhanafy.Resolute"

osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
rm -rf "$APP_DIR/Resolute.app"
if [[ -L "$BIN_DIR/resolute" && "$(readlink "$BIN_DIR/resolute")" == *"Resolute.app/Contents/Helpers/resolute" ]]; then
  rm -f "$BIN_DIR/resolute" 2>/dev/null || echo "Remove the command-line link with: sudo rm \"$BIN_DIR/resolute\""
fi
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "Removed Resolute."
echo "Custom resolution overrides in /Library/Displays and backups in /Library/Application Support/Resolute are untouched."
