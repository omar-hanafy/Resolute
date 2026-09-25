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

# Finish copying before disturbing the installed app. A full disk or failed copy
# must not remove the only working installation.
mkdir -p "$APP_DIR"
STAGING="$(mktemp -d "$APP_DIR/.Resolute-install.XXXXXX")"
APP_PATH="$APP_DIR/Resolute.app"
cleanup() {
  if [[ -d "$STAGING/previous.app" && ! -e "$APP_PATH" && ! -L "$APP_PATH" ]]; then
    if ! mv "$STAGING/previous.app" "$APP_PATH"; then
      echo "Could not restore the previous app; it is preserved at $STAGING/previous.app" >&2
      return
    fi
  fi
  rm -rf "$STAGING"
}
trap cleanup EXIT
ditto dist/Resolute.app "$STAGING/Resolute.app"

# The old process may still be exiting, or may be asking about unsaved custom
# resolutions; either way, swapping the bundle under it would be unsafe.
if ! quit_and_wait; then
  echo "Resolute is still running (it may be asking about unsaved custom resolutions)." >&2
  echo "Quit it and run this script again." >&2
  exit 1
fi

if [[ -L "$APP_PATH" || ( -e "$APP_PATH" && ! -d "$APP_PATH" ) ]]; then
  echo "Refusing to replace a symlink or non-app file at $APP_PATH." >&2
  exit 1
fi
if [[ -d "$APP_PATH" ]]; then mv "$APP_PATH" "$STAGING/previous.app"; fi
mv "$STAGING/Resolute.app" "$APP_PATH"
echo "Installed $APP_DIR/Resolute.app"

CLI="$APP_DIR/Resolute.app/Contents/Helpers/resolute"
if [[ -d "$BIN_DIR" && -w "$BIN_DIR" ]]; then
  if [[ -L "$BIN_DIR/resolute" && "$(readlink "$BIN_DIR/resolute")" == "$CLI" ]] || [[ ! -e "$BIN_DIR/resolute" && ! -L "$BIN_DIR/resolute" ]]; then
    ln -sfn "$CLI" "$BIN_DIR/resolute"
    echo "Linked $BIN_DIR/resolute"
  else
    echo "Kept the existing $BIN_DIR/resolute; the bundled CLI is at $CLI."
  fi
else
  echo "To use the command-line tool, run: sudo mkdir -p \"$BIN_DIR\" && sudo ln -sf \"$CLI\" \"$BIN_DIR/resolute\""
fi

open "$APP_DIR/Resolute.app"
