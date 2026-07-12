#!/usr/bin/env bash
set -euo pipefail

EXPECTED_XCODE_VERSION=${EXPECTED_XCODE_VERSION:-26.6}
IOS_SIMULATOR_NAME=${IOS_SIMULATOR_NAME:-iPhone 17}
XCODEBUILD_BIN=${XCODEBUILD_BIN:-xcodebuild}
MISE_BIN=${MISE_BIN:-mise}
DOCKER_BIN=${DOCKER_BIN:-docker}
XCRUN_BIN=${XCRUN_BIN:-xcrun}

architecture=$(uname -m)
if [[ "$architecture" != arm64 ]]; then
  echo "Runner architecture must be arm64; found $architecture." >&2
  exit 1
fi

xcode_output=$("$XCODEBUILD_BIN" -version)
xcode_version=$(printf '%s\n' "$xcode_output" | sed -n '1{s/\r$//; s/^Xcode[[:space:]]\{1,\}//p;}')
if [[ "$xcode_version" != "$EXPECTED_XCODE_VERSION" ]]; then
  echo "Runner must use Xcode $EXPECTED_XCODE_VERSION; found ${xcode_version:-unknown}." >&2
  printf '%s\n' "$xcode_output" >&2
  exit 1
fi

"$MISE_BIN" install
"$MISE_BIN" exec -- tuist version
"$MISE_BIN" exec -- swiftlint version
"$DOCKER_BIN" info

simulator_output=$("$XCRUN_BIN" simctl list devices available)
if ! grep -Fq "$IOS_SIMULATOR_NAME (" <<<"$simulator_output"; then
  echo "Required Simulator '$IOS_SIMULATOR_NAME' is not available." >&2
  printf '%s\n' "$simulator_output" >&2
  exit 1
fi

echo "iOS runner preflight passed."
