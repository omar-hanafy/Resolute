#!/usr/bin/env bash
# Builds the tests for Intel and runs them under Rosetta, on an Apple silicon Mac.
# `swift test --arch x86_64` cannot do this: its test helper has no Intel slice, but
# xctest has one and runs Swift Testing tests too.
set -euo pipefail
cd "$(dirname "$0")/.."

arch -x86_64 /usr/bin/true 2>/dev/null || { echo "Rosetta is not installed: softwareupdate --install-rosetta" >&2; exit 1; }
SCRATCH=".build/intel"
swift build --build-tests --triple x86_64-apple-macosx14.0 --scratch-path "$SCRATCH"
BIN="$(swift build --build-tests --triple x86_64-apple-macosx14.0 --scratch-path "$SCRATCH" --show-bin-path)"
XCTEST="$(xcrun --find xctest)"
status=0
for bundle in "$BIN"/*Tests.xctest; do
  echo "== $(basename "$bundle")"
  arch -x86_64 "$XCTEST" "$bundle" || status=1
done
exit "$status"
