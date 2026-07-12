#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
validator="$repo_root/Infrastructure/ci/validate-workflows.sh"
workflow_dir="$repo_root/.github/workflows"
invalid_workflow="$workflow_dir/invalid-workflow-fixture.yml"
invalid_shell="$repo_root/Infrastructure/ci/invalid-shell-fixture.sh"
created_github_dir=false
created_workflow_dir=false

if [[ ! -d "$repo_root/.github" ]]; then
  created_github_dir=true
fi
if [[ ! -d "$workflow_dir" ]]; then
  created_workflow_dir=true
fi

cleanup() {
  rm -f "$invalid_workflow" "$invalid_shell"
  if [[ "$created_workflow_dir" == true ]]; then
    rmdir "$workflow_dir" 2>/dev/null || true
  fi
  if [[ "$created_github_dir" == true ]]; then
    rmdir "$repo_root/.github" 2>/dev/null || true
  fi
}
trap cleanup EXIT

mkdir -p "$workflow_dir"
printf 'name: invalid\njobs:\n  build: [\n' > "$invalid_workflow"

if bash "$validator" >/dev/null 2>&1; then
  echo "expected invalid workflow YAML to fail validation" >&2
  exit 1
fi

rm -f "$invalid_workflow"
printf '#!/usr/bin/env bash\nif true; then\n' > "$invalid_shell"

if bash "$validator" >/dev/null 2>&1; then
  echo "expected invalid shell syntax to fail validation" >&2
  exit 1
fi

rm -f "$invalid_shell"
bash "$validator"
