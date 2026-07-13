#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
validator="$repo_root/Infrastructure/ci/validate-workflows.sh"
workflow_dir="$repo_root/.github/workflows"
pr_policy_workflow="$workflow_dir/pr-policy.yml"
backend_workflow="$workflow_dir/backend.yml"
ios_workflow="$workflow_dir/ios.yml"
security_workflow="$workflow_dir/security.yml"
quality_workflow="$workflow_dir/quality.yml"
ci_workflow="$workflow_dir/ci.yml"
runbook="$repo_root/docs/development/gitflow-cicd.md"
readme="$repo_root/README.md"
sonarqube_compose="$repo_root/Infrastructure/sonarqube.compose.yaml"
invalid_workflow="$workflow_dir/invalid-workflow-fixture.yml"
invalid_shell="$repo_root/Infrastructure/ci/invalid-shell-fixture.sh"
temp_dir="$(mktemp -d)"
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
  rm -rf "$temp_dir"
  if [[ "$created_workflow_dir" == true ]]; then
    rmdir "$workflow_dir" 2>/dev/null || true
  fi
  if [[ "$created_github_dir" == true ]]; then
    rmdir "$repo_root/.github" 2>/dev/null || true
  fi
}
trap cleanup EXIT

mkdir -p "$workflow_dir"

if [[ ! -f "$runbook" ]]; then
  echo "required runbook is missing: docs/development/gitflow-cicd.md" >&2
  exit 1
fi

if [[ ! -f "$readme" ]] || ! grep -Fq 'docs/development/gitflow-cicd.md' "$readme"; then
  echo "README.md must link to docs/development/gitflow-cicd.md" >&2
  exit 1
fi

if [[ ! -f "$sonarqube_compose" ]]; then
  echo "required Compose file is missing: Infrastructure/sonarqube.compose.yaml" >&2
  exit 1
fi

validate_sonarqube_compose_security() {
  local candidate="$1"
  grep -Fq -- '127.0.0.1:${SONAR_PORT:-9000}:9000' "$candidate" \
    && ! grep -Fq -- '0.0.0.0:${SONAR_PORT:-9000}:9000' "$candidate" \
    && ! grep -Fq -- '- "${SONAR_PORT:-9000}:9000"' "$candidate"
}

for required_text in \
  'sonarqube:26.7.0.124771-community@sha256:160bd2f6a3485bd09b655ef22dd63c02bd1fa7ba82aa5d9973fd010b8bcca0b3' \
  'postgres:17.10-alpine3.23@sha256:8189a1f6e40904781fc9e2612687877791d21679866db58b1de996b31fc312e4' \
  'condition: service_healthy' \
  'sonar_data:/opt/sonarqube/data' \
  'sonar_db:/var/lib/postgresql/data'; do
  if ! grep -Fq -- "$required_text" "$sonarqube_compose"; then
    echo "sonarqube.compose.yaml is missing required text: $required_text" >&2
    exit 1
  fi
done

if ! validate_sonarqube_compose_security "$sonarqube_compose"; then
  echo "sonarqube.compose.yaml must publish SonarQube only on 127.0.0.1 by default" >&2
  exit 1
fi

cp "$sonarqube_compose" "$temp_dir/all-interfaces-sonarqube.compose.yaml"
sed -i.bak 's/127\.0\.0\.1:/0.0.0.0:/' "$temp_dir/all-interfaces-sonarqube.compose.yaml"
if validate_sonarqube_compose_security "$temp_dir/all-interfaces-sonarqube.compose.yaml"; then
  echo "Compose security contract accepted an all-interface SonarQube mapping" >&2
  exit 1
fi

validate_runbook_targeting() {
  local candidate="$1"
  grep -Fq 'export GH_REPO="jerry-nows/learning-superpower"' "$candidate" \
    && ! grep -Fq 'export GITHUB_REPOSITORY=' "$candidate" \
    && grep -Fq 'docker compose --env-file .env -f Infrastructure/sonarqube.compose.yaml up -d --wait sonarqube' "$candidate"
}

validate_runbook_sonarqube_security() {
  local candidate="$1"
  grep -Fq '127.0.0.1:${SONAR_PORT:-9000}:9000' "$candidate" \
    && grep -Fq 'immediately replace the bootstrap administrator password' "$candidate" \
    && grep -Fq 'least-privilege analysis token' "$candidate" \
    && grep -Fq 'firewall' "$candidate" \
    && grep -Fq 'TLS' "$candidate" \
    && grep -Fq 'reverse proxy' "$candidate"
}

if ! validate_runbook_targeting "$runbook"; then
  echo "gitflow-cicd.md must use GH_REPO and the checked-in SonarQube Compose path" >&2
  exit 1
fi

if ! validate_runbook_sonarqube_security "$runbook"; then
  echo "gitflow-cicd.md must document SonarQube bootstrap and remote-exposure security" >&2
  exit 1
fi

cp "$runbook" "$temp_dir/missing-sonarqube-bootstrap-security.md"
sed -i.bak 's/immediately replace the bootstrap administrator password/retain the bootstrap administrator password/' "$temp_dir/missing-sonarqube-bootstrap-security.md"
if validate_runbook_sonarqube_security "$temp_dir/missing-sonarqube-bootstrap-security.md"; then
  echo "documentation contract accepted missing bootstrap password replacement guidance" >&2
  exit 1
fi

cp "$runbook" "$temp_dir/missing-compose-path.md"
sed -i.bak 's/-f Infrastructure\/sonarqube.compose.yaml/-f unspecified.compose.yaml/g' "$temp_dir/missing-compose-path.md"
if validate_runbook_targeting "$temp_dir/missing-compose-path.md"; then
  echo "documentation contract accepted a missing actual Compose path" >&2
  exit 1
fi

cp "$runbook" "$temp_dir/unsafe-repo-selector.md"
sed -i.bak 's/export GH_REPO="jerry-nows\/learning-superpower"/export GITHUB_REPOSITORY="jerry-nows\/learning-superpower"/' "$temp_dir/unsafe-repo-selector.md"
if validate_runbook_targeting "$temp_dir/unsafe-repo-selector.md"; then
  echo "documentation contract accepted GITHUB_REPOSITORY-only targeting" >&2
  exit 1
fi

for required_text in \
  'runs-on: [self-hosted, macOS, ARM64, commerce-ios]' \
  './config.sh --url "$REPOSITORY_URL" --token "$RUNNER_REGISTRATION_TOKEN" --labels commerce-ios' \
  './svc.sh install' \
  './svc.sh start' \
  './svc.sh status' \
  './svc.sh stop' \
  './svc.sh uninstall' \
  'gh variable set SONAR_HOST_URL --body "$SONAR_HOST_URL"' \
  'gh secret set SONAR_TOKEN' \
  'git switch -c develop main' \
  'git push -u origin develop' \
  'export GH_REPO="jerry-nows/learning-superpower"' \
  'gh api "repos/$GH_REPO/rulesets"' \
  "gh pr comment 3 --body '@sourcery-ai review'" \
  'gh run rerun "$RUN_ID" --failed' \
  'xcrun simctl shutdown all' \
  'xcrun simctl erase all' \
  'open -a Docker' \
  'Infrastructure/sonarqube.compose.yaml' \
  'docker compose --env-file .env -f Infrastructure/sonarqube.compose.yaml up -d --wait sonarqube' \
  'rm -f Backend/coverage.out' \
  'The Sourcery Dashboard is the source of truth' \
  'docs/development/sourcery-review-rules.md' \
  'CodeQL advanced setup' \
  'Disable default setup' \
  'fail closed' \
  'short-lived' \
  'Settings > Actions > Runners' \
  'Rotate SONAR_TOKEN'; do
  if ! grep -Fq -- "$required_text" "$runbook"; then
    echo "gitflow-cicd.md is missing required text: $required_text" >&2
    exit 1
  fi
done

if [[ ! -f "$pr_policy_workflow" ]]; then
  echo "required workflow is missing: .github/workflows/pr-policy.yml" >&2
  exit 1
fi

if [[ ! -f "$backend_workflow" ]]; then
  echo "required workflow is missing: .github/workflows/backend.yml" >&2
  exit 1
fi

if [[ ! -f "$ios_workflow" ]]; then
  echo "required workflow is missing: .github/workflows/ios.yml" >&2
  exit 1
fi

if [[ ! -f "$security_workflow" ]]; then
  echo "required workflow is missing: .github/workflows/security.yml" >&2
  exit 1
fi

if [[ ! -f "$quality_workflow" ]]; then
  echo "required workflow is missing: .github/workflows/quality.yml" >&2
  exit 1
fi

if [[ ! -f "$ci_workflow" ]]; then
  echo "required workflow is missing: .github/workflows/ci.yml" >&2
  exit 1
fi

for required_text in \
  'name: Continuous Integration' \
  'pull_request:' \
  'branches: [main, develop]' \
  'push:' \
  'workflow_dispatch:' \
  'contents: read' \
  'group: ci-${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}' \
  'cancel-in-progress: true' \
  'uses: ./.github/workflows/pr-policy.yml' \
  "base_ref: \${{ github.event_name == 'pull_request' && github.base_ref || 'develop' }}" \
  "head_ref: \${{ github.event_name == 'pull_request' && github.head_ref || 'feature/ci-validation' }}" \
  "is_draft: \${{ github.event_name == 'pull_request' && github.event.pull_request.draft || false }}" \
  "pr_title: \"\${{ github.event_name == 'pull_request' && github.event.pull_request.title || 'ci: validate branch' }}\"" \
  'uses: ./.github/workflows/backend.yml' \
  'uses: ./.github/workflows/ios.yml' \
  'uses: ./.github/workflows/security.yml' \
  'uses: ./.github/workflows/quality.yml' \
  'SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}' \
  'name: Quality Gate' \
  'if: always()' \
  'needs: [policy, backend, ios, security, sonarqube]' \
  "test '\${{ needs.policy.result }}' = success" \
  "test '\${{ needs.backend.result }}' = success" \
  "test '\${{ needs.ios.result }}' = success" \
  "test '\${{ needs.security.result }}' = success" \
  "test '\${{ needs.sonarqube.result }}' = success"; do
  if ! grep -Fq -- "$required_text" "$ci_workflow"; then
    echo "ci.yml is missing required text: $required_text" >&2
    exit 1
  fi
done

if grep -Fq 'secrets: inherit' "$ci_workflow"; then
  echo "ci.yml must pass only the named SonarQube secret" >&2
  exit 1
fi

if [[ "$(grep -Fc 'branches: [main, develop]' "$ci_workflow")" -ne 2 ]]; then
  echo "ci.yml must limit both pull requests and pushes to main/develop" >&2
  exit 1
fi

for required_text in \
  'workflow_call:' \
  'secrets:' \
  'SONAR_TOKEN:' \
  'description: SonarQube authentication token' \
  'required: true' \
  'name: SonarQube' \
  'runs-on: [self-hosted, macOS, ARM64, "${{ '\''commerce-ios'\'' }}"]' \
  'SONAR_HOST_URL: ${{ vars.SONAR_HOST_URL }}' \
  'SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}' \
  'Infrastructure/ci/preflight-sonarqube.sh' \
  'go test -race -coverprofile=coverage.out ./...' \
  '-enableCodeCoverage YES' \
  '-resultBundlePath Build/coverage/CommerceApp.xcresult' \
  'rm -rf Build/coverage/CommerceApp.xcresult' \
  'Infrastructure/ci/xccov-to-sonarqube.sh' \
  'Build/reports/swift-coverage.xml' \
  'uses: SonarSource/sonarqube-scan-action@' \
  '-Dsonar.qualitygate.wait=true'; do
  if ! grep -Fq -- "$required_text" "$quality_workflow"; then
    echo "quality.yml is missing required text: $required_text" >&2
    exit 1
  fi
done

if grep -E 'uses: [^[:space:]]+@' "$quality_workflow" \
  | grep -Evq 'uses: [^[:space:]]+@[0-9a-f]{40}$'; then
  echo "quality.yml actions must be pinned by full commit SHA" >&2
  exit 1
fi

if [[ "$(grep -Fc 'SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}' "$quality_workflow")" -ne 2 ]]; then
  echo "quality.yml must scope SONAR_TOKEN references to the preflight and scanner environments" >&2
  exit 1
fi

if grep -Eq '(^|[[:space:]])echo[^#]*(SONAR_TOKEN|secrets\.SONAR_TOKEN)' "$quality_workflow"; then
  echo "quality.yml must never echo the SonarQube token" >&2
  exit 1
fi

if grep -Eq -- '-Dsonar\.(token|login|password)=' "$quality_workflow"; then
  echo "quality.yml must pass SonarQube credentials only through the environment" >&2
  exit 1
fi

for required_text in \
  'workflow_call:' \
  'runs-on: ubuntu-24.04' \
  'name: Security' \
  'security-events: write' \
  'github/codeql-action/init@' \
  'languages: go' \
  'build-mode: manual' \
  'go-version-file: Backend/go.mod' \
  'working-directory: Backend' \
  'run: go build ./...' \
  'github/codeql-action/analyze@' \
  'actions/dependency-review-action@' \
  "if: github.event_name == 'pull_request'" \
  'GITLEAKS_VERSION: 8.30.1' \
  'GITLEAKS_ARCHIVE_SHA256: 551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb' \
  'detect --source .' \
  'aquasecurity/trivy-action@' \
  'severity: HIGH,CRITICAL' \
  'exit-code: 1' \
  'CycloneDX/gh-gomod-generate-sbom@' \
  'sbom.cdx.json' \
  'retention-days: 7'; do
  if ! grep -Fq -- "$required_text" "$security_workflow"; then
    echo "security.yml is missing required text: $required_text" >&2
    exit 1
  fi
done

if grep -Eq 'gitleaks/gitleaks-action@|GITLEAKS_LICENSE|build-mode: none' "$security_workflow"; then
  echo "security.yml must use license-free pinned Gitleaks OSS and a supported CodeQL Go build mode" >&2
  exit 1
fi

if grep -E 'uses: [^[:space:]]+@' "$security_workflow" \
  | grep -Evq 'uses: [^[:space:]]+@[0-9a-f]{40}([[:space:]]+#.*)?$'; then
  echo "security.yml actions must be pinned by full commit SHA" >&2
  exit 1
fi

for required_text in \
  'workflow_call:' \
  'name: iOS' \
  'runs-on: [self-hosted, macOS, ARM64, "${{ '\''commerce-ios'\'' }}"]' \
  'timeout-minutes: 45' \
  'group: ios-${{ github.event.pull_request.number || github.ref }}' \
  'Infrastructure/ci/preflight-ios-runner.sh' \
  'xcrun simctl boot "iPhone 17"' \
  'mise exec -- swiftlint lint --strict' \
  'make ios-test-packages' \
  '-scheme CommerceApp' \
  "-destination 'platform=iOS Simulator,name=iPhone 17'" \
  '-resultBundlePath TestResults/CommerceApp.xcresult' \
  'make ios-build-unsigned' \
  'if: failure()' \
  'retention-days: 7'; do
  if ! grep -Fq -- "$required_text" "$ios_workflow"; then
    echo "ios.yml is missing required text: $required_text" >&2
    exit 1
  fi
done

if grep -E 'uses: [^[:space:]]+@' "$ios_workflow" \
  | grep -Evq 'uses: [^[:space:]]+@[0-9a-f]{40}$'; then
  echo "ios.yml actions must be pinned by full commit SHA" >&2
  exit 1
fi

for required_text in \
  'workflow_call:' \
  'runs-on: ubuntu-24.04' \
  'name: Backend' \
  'working-directory: Backend' \
  'go-version-file: Backend/go.mod' \
  'cache: true' \
  'gofmt -l' \
  'go vet ./...' \
  'honnef.co/go/tools/cmd/staticcheck@2025.1.1' \
  'staticcheck ./...' \
  'go test -race -coverprofile=coverage.out ./...' \
  'path: Backend/coverage.out'; do
  if ! grep -Fq "$required_text" "$backend_workflow"; then
    echo "backend.yml is missing required text: $required_text" >&2
    exit 1
  fi
done

if grep -Fq 'gofmt -w' "$backend_workflow"; then
  echo "backend.yml must check formatting without rewriting sources" >&2
  exit 1
fi

if grep -E 'uses: [^[:space:]]+@' "$backend_workflow" \
  | grep -Evq 'uses: [^[:space:]]+@[0-9a-f]{40}$'; then
  echo "backend.yml actions must be pinned by full commit SHA" >&2
  exit 1
fi

for required_text in \
  'workflow_call:' \
  'workflow_dispatch:' \
  'permissions:' \
  'contents: read' \
  'name: PR Policy'; do
  if ! grep -Fq "$required_text" "$pr_policy_workflow"; then
    echo "pr-policy.yml is missing required text: $required_text" >&2
    exit 1
  fi
done

workflow_call_inputs="$({
  awk '
    /^  workflow_call:$/ { in_workflow_call = 1; next }
    /^  workflow_dispatch:$/ { in_workflow_call = 0 }
    in_workflow_call && /^      [a-z_]+:$/ {
      input = $1
      sub(/:$/, "", input)
      print input
    }
  ' "$pr_policy_workflow"
} | sort)"
expected_inputs=$'base_ref\nhead_ref\nis_draft\npr_title'
if [[ "$workflow_call_inputs" != "$expected_inputs" ]]; then
  echo "pr-policy.yml workflow_call inputs must be exactly: base_ref, head_ref, is_draft, pr_title" >&2
  exit 1
fi

permissions_block="$(awk '
  /^permissions:$/ { in_permissions = 1 }
  in_permissions && /^[^[:space:]]/ && !/^permissions:$/ { exit }
  in_permissions && NF { print }
' "$pr_policy_workflow")"
if [[ "$permissions_block" != $'permissions:\n  contents: read' ]]; then
  echo "pr-policy.yml permissions must be exactly: contents: read" >&2
  exit 1
fi

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
