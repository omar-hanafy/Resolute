#!/usr/bin/env bash
# Installs Resolute.app and links the resolute command.
#   RESOLUTE_APP_DIR=~/Applications RESOLUTE_BIN_DIR=~/.local/bin Scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_DIR="${RESOLUTE_APP_DIR:-/Applications}"
BIN_DIR="${RESOLUTE_BIN_DIR:-/usr/local/bin}"
BUNDLE_ID="com.omarhanafy.Resolute"

[[ -d dist/Resolute.app ]] || Scripts/build-app.sh

osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
rm -rf "$APP_DIR/Resolute.app"
ditto dist/Resolute.app "$APP_DIR/Resolute.app"
echo "Installed $APP_DIR/Resolute.app"

CLI="$APP_DIR/Resolute.app/Contents/Helpers/resolute"
if [[ -d "$BIN_DIR" && -w "$BIN_DIR" ]]; then
  ln -sf "$CLI" "$BIN_DIR/resolute"
  echo "Linked $BIN_DIR/resolute"
else
  echo "To use the command-line tool, run: sudo ln -sf \"$CLI\" \"$BIN_DIR/resolute\""
fi

open "$APP_DIR/Resolute.app"
