#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

cat >"$temporary_directory/curl" <<'MOCK'
#!/usr/bin/env bash
printf '{"status":"ok"}\n'
MOCK
cat >"$temporary_directory/docker" <<'MOCK'
#!/usr/bin/env bash
if [[ " $* " == *" redis "* ]]; then
  printf 'PONG\n'
fi
exit 0
MOCK
cat >"$temporary_directory/mkcert" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_CA_ROOT:?}"
MOCK
chmod +x "$temporary_directory/curl" "$temporary_directory/docker" "$temporary_directory/mkcert"
touch "$temporary_directory/rootCA.pem"

output="$(
  FAKE_CA_ROOT="$temporary_directory" \
  PATH="$temporary_directory:/usr/bin:/bin" \
  ENV_FILE="$root/.env.example" \
    "$root/Infrastructure/scripts/smoke.sh"
)"
[[ "$output" == *"foundation smoke passed"* ]]
