#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

cat >"$temporary_directory/mkcert" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${MOCK_ARGS_FILE:?}"
while (($#)); do
  case "$1" in
    -cert-file) certificate="$2"; shift 2 ;;
    -key-file) private_key="$2"; shift 2 ;;
    *) shift ;;
  esac
done
touch "$certificate" "$private_key"
MOCK
chmod +x "$temporary_directory/mkcert"

MOCK_ARGS_FILE="$temporary_directory/arguments" \
CERT_DIR="$temporary_directory/certs" \
COMMERCE_HOST=commerce.local \
COMMERCE_LAN_IP=192.0.2.10 \
PATH="$temporary_directory:/usr/bin:/bin" \
  "$root/Infrastructure/scripts/create-certs.sh"

test -f "$temporary_directory/certs/commerce.local.pem"
test -f "$temporary_directory/certs/commerce.local-key.pem"
grep -q 'commerce.local' "$temporary_directory/arguments"
grep -q '192.0.2.10' "$temporary_directory/arguments"
permissions="$(stat -f '%Lp' "$temporary_directory/certs/commerce.local-key.pem" 2>/dev/null || stat -c '%a' "$temporary_directory/certs/commerce.local-key.pem")"
test "$permissions" = "600"
