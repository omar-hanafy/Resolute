#!/usr/bin/env bash
# Shared functions for install.sh, uninstall.sh and release.sh. Callers set BUNDLE_ID and
# source this file before calling quit_and_wait.

# How long to wait for the app to quit, and how often to check, in seconds; and how long
# the app gets to turn Launch at Login off. Overridable so tests don't wait them out.
: "${RESOLUTE_QUIT_TIMEOUT:=10}"
: "${RESOLUTE_QUIT_POLL_INTERVAL:=1}"
: "${RESOLUTE_UNREGISTER_TIMEOUT:=5}"

# True when the app identified by BUNDLE_ID is running.
app_is_running() {
  [[ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null)" == "true" ]]
}

# Turns off Launch at Login through the app at $1, if it is a build that knows how, and
# says how to do it by hand when that fails. Never fails itself.
unregister_login_item() {
  local app="$1" version output pid status=0 waited=0
  local by_hand="Turn it off in System Settings > General > Login Items."
  version="$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)"
  case "$version" in
    # These builds start the whole menu-bar app for a flag they don't know.
    "" | 0.0.* | 0.1.*)
      echo "If you turned on Launch at Login, turn it off in System Settings > General > Login Items."
      return 0
      ;;
  esac
  output="$(mktemp)"
  # A build that still starts the app instead (a 0.2 development build from before the
  # flag) gets a few seconds and is then stopped.
  "$app/Contents/MacOS/Resolute" --unregister-login-item >"$output" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && (( waited < RESOLUTE_UNREGISTER_TIMEOUT * 10 )); do
    sleep 0.1
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    echo "Could not turn off Launch at Login: the app did not answer."
    echo "$by_hand"
  else
    wait "$pid" || status=$?
    if (( status != 0 )); then
      echo "Could not turn off Launch at Login: $(tr '\n' ' ' < "$output" | sed 's/ *$//')"
      echo "$by_hand"
    fi
  fi
  rm -f "$output"
  return 0
}

# Asks the app to quit and waits for it to exit, up to RESOLUTE_QUIT_TIMEOUT seconds.
# Succeeds at once if the app was not running. Fails if it is still running at the
# deadline (for example because it is asking about unsaved changes); the caller decides
# what to do about that.
quit_and_wait() {
  app_is_running || return 0
  echo "Waiting for Resolute to quit…"
  # Sent without waiting for the answer: the app may be asking about unsaved custom
  # resolutions, and osascript would otherwise wait up to two minutes before the timed
  # wait below even starts.
  osascript -e "if application id \"$BUNDLE_ID\" is running then" -e "ignoring application responses" \
    -e "tell application id \"$BUNDLE_ID\" to quit" -e "end ignoring" -e "end if" >/dev/null 2>&1 || true

  local deadline
  deadline=$(( $(date +%s) + RESOLUTE_QUIT_TIMEOUT ))
  while app_is_running; do
    (( $(date +%s) < deadline )) || return 1
    sleep "$RESOLUTE_QUIT_POLL_INTERVAL"
  done
  return 0
}

# Prints the CHANGELOG section for version $1 from file $2, without its heading or the
# blank lines around it. Prints nothing when the file has no such section.
release_notes() {
  awk -v heading="## $1" '
    $0 == heading || index($0, heading " ") == 1 { found = 1; next }
    found && /^## / { exit }
    found { lines[++count] = $0 }
    END {
      first = 1
      while (first <= count && lines[first] == "") first++
      last = count
      while (last >= first && lines[last] == "") last--
      for (i = first; i <= last; i++) print lines[i]
    }
  ' "$2"
}

