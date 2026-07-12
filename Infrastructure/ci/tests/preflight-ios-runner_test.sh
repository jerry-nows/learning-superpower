#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PREFLIGHT="$ROOT_DIR/Infrastructure/ci/preflight-ios-runner.sh"
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

write_fixture_commands() {
  local architecture=${1:-arm64}
  local xcode_version=${2:-26.6}
  local simulator_name=${3:-iPhone 17}
  local bin_dir="$FIXTURE_DIR/bin"

  rm -rf "$bin_dir"
  mkdir -p "$bin_dir"
  : >"$FIXTURE_DIR/commands.log"

  cat >"$bin_dir/uname" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$architecture'
EOF
  cat >"$bin_dir/xcodebuild" <<EOF
#!/usr/bin/env bash
printf 'xcodebuild %s\n' "\$*" >>"\$FIXTURE_LOG"
printf 'Xcode %s\nBuild version 17G99\n' '$xcode_version'
EOF
  cat >"$bin_dir/mise" <<'EOF'
#!/usr/bin/env bash
printf 'mise %s\n' "$*" >>"$FIXTURE_LOG"
case "${1:-}" in
  install) exit 0 ;;
  exec)
    case "${3:-}" in
      tuist) printf '4.95.0\n' ;;
      swiftlint) printf '0.59.1\n' ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
EOF
  cat >"$bin_dir/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$FIXTURE_LOG"
[[ "${1:-}" == info ]]
EOF
  cat >"$bin_dir/xcrun" <<EOF
#!/usr/bin/env bash
printf 'xcrun %s\n' "\$*" >>"\$FIXTURE_LOG"
printf '%s\n' '== Devices ==' '-- iOS 26.6 --' '    $simulator_name (00000000-0000-0000-0000-000000000000) (Shutdown)'
EOF
  chmod +x "$bin_dir"/*
}

run_preflight() {
  local bin_dir="$FIXTURE_DIR/bin"
  PATH="$bin_dir:$PATH" \
    FIXTURE_LOG="$FIXTURE_DIR/commands.log" \
    XCODEBUILD_BIN="$bin_dir/xcodebuild" \
    MISE_BIN="$bin_dir/mise" \
    DOCKER_BIN="$bin_dir/docker" \
    XCRUN_BIN="$bin_dir/xcrun" \
    "$PREFLIGHT" 2>&1
}

assert_command_ran() {
  local command=$1
  grep -Fxq "$command" "$FIXTURE_DIR/commands.log" || fail "command did not run: $command"
}

assert_fails_with() {
  local expected=$1
  local output
  if output=$(run_preflight); then
    fail "preflight unexpectedly succeeded; wanted: $expected"
  fi
  [[ "$output" == *"$expected"* ]] || fail "expected '$expected' in output: $output"
}

write_fixture_commands
run_preflight >/dev/null || fail "valid runner fixture was rejected"
assert_command_ran "xcodebuild -version"
assert_command_ran "mise install"
assert_command_ran "mise exec -- tuist version"
assert_command_ran "mise exec -- swiftlint version"
assert_command_ran "docker info"
assert_command_ran "xcrun simctl list devices available"

write_fixture_commands x86_64
assert_fails_with "arm64"

write_fixture_commands arm64 26.5
assert_fails_with "Xcode 26.6"

write_fixture_commands arm64 26.6 "iPhone 16"
assert_fails_with "iPhone 17"

echo "PASS: iOS runner preflight fixtures"
