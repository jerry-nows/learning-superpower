#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/Infrastructure/scripts/product-e2e.sh"

[[ -x "$script" ]] || { echo "product e2e script must be executable" >&2; exit 1; }
for endpoint in '/v1/auth/login' '/v1/products?page=1&page_size=20' '/v1/products?search=headphones' '/v1/products/00000000-0000-4000-8000-000000000101'; do
  grep -Fq "$endpoint" "$script"
done
grep -Fq 'SEED_USER_EMAIL' "$script"
grep -Fq 'SEED_USER_PASSWORD' "$script"
grep -Fq 'mktemp -d' "$script"
grep -Fq 'chmod 700' "$script"
grep -Fq "trap 'rm -rf -- \"\$temporary_directory\"' EXIT" "$script"
grep -Fq 'product e2e passed' "$script"
! grep -Eq 'cat ("?\$?[^ ]*(response|token)|[^ ]*password)' "$script"

echo 'PASS: product e2e contract'
