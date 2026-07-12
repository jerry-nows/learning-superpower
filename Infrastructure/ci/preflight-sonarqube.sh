#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -n "${SONAR_HOST_URL:-}" ]] || fail "SONAR_HOST_URL is required"
[[ -n "${SONAR_TOKEN:-}" ]] || fail "SONAR_TOKEN is required"

CURL_BIN="${CURL_BIN:-curl}"
status_url="${SONAR_HOST_URL%/}/api/system/status"

if ! response="$("$CURL_BIN" --fail --silent --show-error "$status_url" 2>/dev/null)"; then
  fail "Unable to reach SonarQube at the configured SONAR_HOST_URL"
fi

status="$(printf '%s\n' "$response" | sed -nE 's/.*"status"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)"
[[ -n "$status" ]] || fail "SonarQube returned an invalid system status response"
[[ "$status" == "UP" ]] || fail "SonarQube is not UP"

echo "SonarQube preflight passed."
