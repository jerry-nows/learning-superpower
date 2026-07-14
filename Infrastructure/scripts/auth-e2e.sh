#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
environment_file="${ENV_FILE:-$root/.env}"
if [[ ! -f "$environment_file" ]]; then
  environment_file="$root/.env.example"
fi

set -a
# shellcheck disable=SC1090
source "$environment_file"
set +a

: "${SEED_USER_EMAIL:?SEED_USER_EMAIL is required}"
: "${SEED_USER_PASSWORD:?SEED_USER_PASSWORD is required}"
host="${COMMERCE_HOST:-commerce.local}"
port="${HTTPS_PORT:-8443}"
ca_file="$(mkcert -CAROOT)/rootCA.pem"
base_url="https://$host:$port"

temporary_directory="$(mktemp -d)"
chmod 700 "$temporary_directory"
trap 'rm -rf -- "$temporary_directory"' EXIT
for file in "$temporary_directory"/*; do
  [[ -e "$file" ]] && chmod 600 "$file"
done

request() {
  local method="$1" endpoint="$2" body_file="$3" output_file="$4"
  local status
  local -a curl_args=(
    --silent --show-error --location
    --connect-timeout 5 --max-time 15
    --cacert "$ca_file" --resolve "$host:$port:127.0.0.1"
    --request "$method" -H 'Content-Type: application/json'
    --output "$output_file" --write-out '%{http_code}'
  )
  if [[ -n "$body_file" ]]; then
    curl_args+=(--data-binary "@$body_file")
  fi
  if ! status="$(curl "${curl_args[@]}" \
    "$base_url$endpoint" 2>"$temporary_directory/curl.err")"; then
    return 1
  fi
  printf '%s' "$status"
}

expect_status() {
  local expected="$1" actual="$2"
  if [[ "$actual" != "$expected" ]]; then
    return 1
  fi
}

write_login_payload() {
  SEED_USER_EMAIL="$SEED_USER_EMAIL" SEED_USER_PASSWORD="$SEED_USER_PASSWORD" \
    python3 - "$1" <<'PY'
import json
import os
import pathlib
import sys

pathlib.Path(sys.argv[1]).write_text(json.dumps({
    "email": os.environ["SEED_USER_EMAIL"],
    "password": os.environ["SEED_USER_PASSWORD"],
}), encoding="utf-8")
PY
  chmod 600 "$1"
}

write_refresh_payload() {
  REFRESH_TOKEN="$2" python3 - "$1" <<'PY'
import json
import os
import pathlib
import sys

pathlib.Path(sys.argv[1]).write_text(json.dumps({
    "refresh_token": os.environ["REFRESH_TOKEN"],
}), encoding="utf-8")
PY
  chmod 600 "$1"
}

extract_tokens() {
  python3 - "$1" "$2" "$3" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
tokens = data.get("tokens", {})
access = tokens.get("access_token")
refresh = tokens.get("refresh_token")
if not isinstance(access, str) or not access or not isinstance(refresh, str) or not refresh:
    raise SystemExit(1)
pathlib.Path(sys.argv[2]).write_text(access, encoding="utf-8")
pathlib.Path(sys.argv[3]).write_text(refresh, encoding="utf-8")
PY
  chmod 600 "$2" "$3"
}

die() {
  printf 'auth e2e failed\n' >&2
  exit 1
}

login_payload="$temporary_directory/login.json"
login_response="$temporary_directory/login.response"
refresh_payload="$temporary_directory/refresh.json"
refresh_response="$temporary_directory/refresh.response"
access_token="$temporary_directory/access.token"
refresh_token="$temporary_directory/refresh.token"
next_access_token="$temporary_directory/next-access.token"
next_refresh_token="$temporary_directory/next-refresh.token"

write_login_payload "$login_payload" || die
expect_status 200 "$(request POST /v1/auth/login "$login_payload" "$login_response")" || die
extract_tokens "$login_response" "$access_token" "$refresh_token" || die

write_refresh_payload "$refresh_payload" "$(<"$refresh_token")" || die
expect_status 200 "$(request POST /v1/auth/refresh "$refresh_payload" "$refresh_response")" || die
extract_tokens "$refresh_response" "$next_access_token" "$next_refresh_token" || die
if [[ "$(<"$refresh_token")" == "$(<"$next_refresh_token")" ]]; then
  die
fi

# Reusing the rotated token revokes the entire refresh-token family.
expect_status 401 "$(request POST /v1/auth/refresh "$refresh_payload" "$temporary_directory/reuse.response")" || die
write_refresh_payload "$refresh_payload" "$(<"$next_refresh_token")" || die
expect_status 401 "$(request POST /v1/auth/refresh "$refresh_payload" "$temporary_directory/family.response")" || die

# A fresh family proves logout revokes sessions independently of reuse detection.
expect_status 200 "$(request POST /v1/auth/login "$login_payload" "$login_response")" || die
extract_tokens "$login_response" "$access_token" "$refresh_token" || die
if ! status="$(curl --silent --show-error --location \
  --connect-timeout 5 --max-time 15 \
  --cacert "$ca_file" --resolve "$host:$port:127.0.0.1" \
  --request POST -H "Authorization: Bearer $(<"$access_token")" \
  --output "$temporary_directory/logout.response" --write-out '%{http_code}' \
  "$base_url/v1/auth/logout" 2>"$temporary_directory/curl.err")"; then
  die
fi
expect_status 204 "$status" || die
write_refresh_payload "$refresh_payload" "$(<"$refresh_token")" || die
expect_status 401 "$(request POST /v1/auth/refresh "$refresh_payload" "$temporary_directory/post-logout.response")" || die

printf 'auth e2e passed\n'
