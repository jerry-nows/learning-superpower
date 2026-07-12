#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fake_bin="$(mktemp -d)"
trap 'rm -rf "$fake_bin"' EXIT

for tool in go docker mkcert make python3; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/$tool"
  chmod +x "$fake_bin/$tool"
done

output="$(PATH="$fake_bin:/usr/bin:/bin" "$root/Infrastructure/scripts/check-tools.sh")"
[[ "$output" == "foundation tools available" ]]

rm "$fake_bin/mkcert"
if PATH="$fake_bin:/usr/bin:/bin" "$root/Infrastructure/scripts/check-tools.sh" 2>"$fake_bin/error"; then
  echo "expected missing mkcert to fail" >&2
  exit 1
fi
grep -qx "missing required tool: mkcert" "$fake_bin/error"
