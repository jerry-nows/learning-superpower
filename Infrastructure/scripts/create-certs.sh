#!/usr/bin/env bash
set -euo pipefail

if ! command -v mkcert >/dev/null 2>&1; then
  echo "missing required tool: mkcert" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
certificate_directory="${CERT_DIR:-$root/Infrastructure/certs}"
host="${COMMERCE_HOST:-commerce.local}"
lan_ip="${COMMERCE_LAN_IP:-}"
mkdir -p "$certificate_directory"

names=("$host" localhost 127.0.0.1 ::1)
if [[ -n "$lan_ip" ]]; then
  names+=("$lan_ip")
fi

mkcert \
  -cert-file "$certificate_directory/commerce.local.pem" \
  -key-file "$certificate_directory/commerce.local-key.pem" \
  "${names[@]}"
chmod 600 "$certificate_directory/commerce.local-key.pem"
echo "certificate created for: ${names[*]}"
