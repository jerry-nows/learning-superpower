#!/usr/bin/env bash
set -euo pipefail

EXPECTED_XCODE_VERSION=${EXPECTED_XCODE_VERSION:-26.6}
EXPECTED_TUIST_VERSION=4.202.1
EXPECTED_SWIFTLINT_VERSION=0.65.0
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

if ! "$MISE_BIN" install; then
  echo "mise install failed; run 'mise install' and resolve the reported tool installation error." >&2
  exit 1
fi

if ! tuist_output=$("$MISE_BIN" exec -- tuist version 2>&1); then
  echo "Unable to read Tuist version; run 'mise install tuist' and verify the Tuist pin." >&2
  printf '%s\n' "$tuist_output" >&2
  exit 1
fi
tuist_version=$(printf '%s\n' "$tuist_output" | sed -n '1{s/\r$//;p;}')
if [[ "$tuist_version" != "$EXPECTED_TUIST_VERSION" ]]; then
  echo "Runner must use Tuist $EXPECTED_TUIST_VERSION; found ${tuist_version:-unknown}. Run 'mise install tuist' to install the pinned version." >&2
  exit 1
fi

if ! swiftlint_output=$("$MISE_BIN" exec -- swiftlint version 2>&1); then
  echo "Unable to read SwiftLint version; run 'mise install swiftlint' and verify the SwiftLint pin." >&2
  printf '%s\n' "$swiftlint_output" >&2
  exit 1
fi
swiftlint_version=$(printf '%s\n' "$swiftlint_output" | sed -n '1{s/\r$//;p;}')
if [[ "$swiftlint_version" != "$EXPECTED_SWIFTLINT_VERSION" ]]; then
  echo "Runner must use SwiftLint $EXPECTED_SWIFTLINT_VERSION; found ${swiftlint_version:-unknown}. Run 'mise install swiftlint' to install the pinned version." >&2
  exit 1
fi

if ! "$DOCKER_BIN" info; then
  echo "Docker is unavailable; start Docker Desktop and wait for the Docker engine to become ready." >&2
  exit 1
fi

if ! simulator_output=$("$XCRUN_BIN" simctl list devices available 2>&1); then
  echo "Unable to list available Simulators; verify Xcode command-line tools with 'xcode-select -p'." >&2
  printf '%s\n' "$simulator_output" >&2
  exit 1
fi
if ! grep -Fq "$IOS_SIMULATOR_NAME (" <<<"$simulator_output"; then
  echo "Required Simulator '$IOS_SIMULATOR_NAME' is not available." >&2
  printf '%s\n' "$simulator_output" >&2
  exit 1
fi

echo "iOS runner preflight passed."
