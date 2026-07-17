#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/Infrastructure/scripts/auth-e2e.sh"

[[ -x "$script" ]] || { echo "auth-e2e script must be executable" >&2; exit 1; }
grep -Fq 'SEED_USER_EMAIL' "$script"
grep -Fq 'SEED_USER_PASSWORD' "$script"
grep -Fq 'mktemp -d' "$script"
grep -Fq 'chmod 700' "$script"
grep -Fq 'chmod 600' "$script"
grep -Fq "trap 'rm -rf -- \"\$temporary_directory\"' EXIT" "$script"
for endpoint in '/v1/auth/login' '/v1/auth/refresh' '/v1/auth/logout'; do
  grep -Fq "$endpoint" "$script"
done
grep -Fq 'expect_status 200' "$script"
grep -Fq 'expect_status 401' "$script"
grep -Fq 'expect_status 204' "$script"
grep -Fq 'auth e2e passed' "$script"
! grep -Eq 'cat ("?\$?[^ ]*(response|token)|[^ ]*password)' "$script"

echo 'PASS: auth e2e script contract'
