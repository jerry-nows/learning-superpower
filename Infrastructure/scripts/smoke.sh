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

host="${COMMERCE_HOST:-commerce.local}"
port="${HTTPS_PORT:-8443}"
ca_file="$(mkcert -CAROOT)/rootCA.pem"
compose=(docker compose --env-file "$environment_file" -f "$root/Infrastructure/compose.yaml")

curl --fail --silent --show-error \
  --cacert "$ca_file" \
  --resolve "$host:$port:127.0.0.1" \
  "https://$host:$port/healthz" | grep -qx '{"status":"ok"}'
${compose[@]} exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null
${compose[@]} exec -T redis redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -qx PONG
${compose[@]} exec -T kafka \
  /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 >/dev/null
echo "foundation smoke passed"
