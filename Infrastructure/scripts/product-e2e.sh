#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
environment_file="${ENV_FILE:-$root/.env}"
[[ -f "$environment_file" ]] || environment_file="$root/.env.example"
set -a
# shellcheck disable=SC1090
source "$environment_file"
set +a
: "${SEED_USER_EMAIL:?SEED_USER_EMAIL is required}"
: "${SEED_USER_PASSWORD:?SEED_USER_PASSWORD is required}"

host="${COMMERCE_HOST:-commerce.local}"
port="${HTTPS_PORT:-8443}"
base_url="https://$host:$port"
ca_file="$(mkcert -CAROOT)/rootCA.pem"
temporary_directory="$(mktemp -d)"
chmod 700 "$temporary_directory"
trap 'rm -rf -- "$temporary_directory"' EXIT
umask 077

python3 - "$temporary_directory/login.json" <<'PY'
import json, os, pathlib, sys
pathlib.Path(sys.argv[1]).write_text(json.dumps({"email": os.environ["SEED_USER_EMAIL"], "password": os.environ["SEED_USER_PASSWORD"]}), encoding="utf-8")
PY
curl_args=(--silent --show-error --location --connect-timeout 5 --max-time 15 --cacert "$ca_file" --resolve "$host:$port:127.0.0.1" -H 'Content-Type: application/json')
curl "${curl_args[@]}" --data-binary "@$temporary_directory/login.json" "$base_url/v1/auth/login" --output "$temporary_directory/login.response"
python3 - "$temporary_directory/login.response" "$temporary_directory/access.token" <<'PY'
import json, pathlib, sys
token = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))["tokens"]["access_token"]
if not isinstance(token, str) or not token: raise SystemExit(1)
pathlib.Path(sys.argv[2]).write_text(token, encoding="utf-8")
PY

auth_header="Authorization: Bearer $(<"$temporary_directory/access.token")"
curl "${curl_args[@]}" --header "$auth_header" "$base_url/v1/products?page=1&page_size=20" --output "$temporary_directory/list.response"
curl "${curl_args[@]}" --header "$auth_header" "$base_url/v1/products?search=headphones" --output "$temporary_directory/search.response"
curl "${curl_args[@]}" --header "$auth_header" "$base_url/v1/products/00000000-0000-4000-8000-000000000101" --output "$temporary_directory/detail.response"
python3 - "$temporary_directory/list.response" "$temporary_directory/search.response" "$temporary_directory/detail.response" <<'PY'
import json, pathlib, sys
list_data, search_data, detail = [json.loads(pathlib.Path(p).read_text(encoding="utf-8")) for p in sys.argv[1:]]
if list_data.get("total", 0) < 1 or not list_data.get("items"): raise SystemExit(1)
if search_data.get("total") != 1 or search_data["items"][0].get("name") != "Wireless Headphones": raise SystemExit(1)
if detail.get("name") != "Wireless Headphones": raise SystemExit(1)
PY
printf 'product e2e passed\n'
