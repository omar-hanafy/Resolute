#!/usr/bin/env bash
# Shared functions for install.sh and uninstall.sh. Callers set BUNDLE_ID and source
# this file before calling quit_and_wait.

# How long to wait for the app to quit, and how often to check, in seconds. Overridable
# so tests don't have to wait out the full timeout.
: "${RESOLUTE_QUIT_TIMEOUT:=10}"
: "${RESOLUTE_QUIT_POLL_INTERVAL:=1}"

# True when the app identified by BUNDLE_ID is running.
app_is_running() {
  [[ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null)" == "true" ]]
}

# Turns off Launch at Login through the app at $1, if it is a build that knows how.
# Builds before 0.2 start the whole menu-bar app for a flag they don't know, which would
# leave the caller waiting on it, so they are not asked.
unregister_login_item() {
  local app="$1" version
  version="$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)"
  case "$version" in
    "" | 0.0.* | 0.1.*)
      echo "If you turned on Launch at Login, turn it off in System Settings > General > Login Items."
      return 0
      ;;
  esac
  "$app/Contents/MacOS/Resolute" --unregister-login-item >/dev/null 2>&1 || true
}

# Asks the app to quit and waits for it to exit, up to RESOLUTE_QUIT_TIMEOUT seconds.
# Succeeds at once if the app was not running. Fails if it is still running at the
# deadline (for example because it is asking about unsaved changes); the caller decides
# what to do about that.
quit_and_wait() {
  osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" \
    >/dev/null 2>&1 || true

  local deadline
  deadline=$(( $(date +%s) + RESOLUTE_QUIT_TIMEOUT ))
  while app_is_running; do
    (( $(date +%s) < deadline )) || return 1
    sleep "$RESOLUTE_QUIT_POLL_INTERVAL"
  done
  return 0
}
