#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

for tool in actionlint yamllint; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool '$tool' is not installed" >&2
    exit 127
  fi
done

workflow_files=()
if [[ -d "$repo_root/.github/workflows" ]]; then
  while IFS= read -r -d '' file; do
    workflow_files+=("$file")
  done < <(find "$repo_root/.github/workflows" -type f -name '*.yml' -print0 | sort -z)
fi

if ((${#workflow_files[@]} > 0)); then
  yamllint --config-file "$repo_root/.yamllint.yml" "${workflow_files[@]}"
  (
    cd "$repo_root"
    actionlint "${workflow_files[@]}"
  )
fi

while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(
  find "$repo_root/Infrastructure/ci" \
    -type f \
    -name '*.sh' \
    -not -path '*/tests/fixtures/*' \
    -print0 | sort -z
)
