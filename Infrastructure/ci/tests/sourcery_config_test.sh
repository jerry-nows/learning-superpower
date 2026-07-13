#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
config="${SOURCERY_CONFIG_PATH:-$repo_root/.sourcery.yaml}"
rules="${SOURCERY_RULES_PATH:-$repo_root/docs/development/sourcery-review-rules.md}"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$config" ]] || fail '.sourcery.yaml is absent'
[[ -f "$rules" ]] || fail 'Sourcery Dashboard review-rules artifact is absent'

ruby -e '
  require "yaml"
  config = YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], aliases: false)
  abort "configuration must be a YAML mapping" unless config.is_a?(Hash)
  abort "legacy configuration must contain only version" unless config.keys == ["version"]
  abort "version must be the string schema version 1" unless config["version"] == "1"
' "$config" || fail 'configuration is not a meaningful minimal legacy Sourcery YAML document'

for required in \
  '# Sourcery Dashboard Review Rules' \
  'Dashboard is the source of truth' \
  'Apps/**/*.swift,Packages/**/*.swift' \
  'Swift 6 and MainActor correctness' \
  'Blocking: Yes' \
  'Clean Architecture, MVVM-C, Factory, and XCoordinator' \
  'Blocking: No' \
  'Backend/**/*.go' \
  'Go, JWT, and OWASP' \
  '**/*' \
  'correctness, security, and evidence' \
  'formatting noise' \
  '**/*Tests.swift,**/*_test.go,Apps/**/UITests/**/*.swift' \
  'Regression tests, mocks, and UI recovery' \
  'Reload the Dashboard' \
  'bash Infrastructure/ci/tests/sourcery_config_test.sh'; do
  grep -Fq "$required" "$rules" || fail "missing Dashboard rule artifact content: $required"
done

[[ "$(grep -Fc '## Rule ' "$rules")" -eq 5 ]] || fail 'Dashboard rule artifact must contain exactly five rules'
[[ "$(grep -Fc 'Blocking: Yes' "$rules")" -eq 3 ]] || fail 'Dashboard rule artifact must contain exactly three blocking rules'
[[ "$(grep -Fc 'Blocking: No' "$rules")" -eq 2 ]] || fail 'Dashboard rule artifact must contain exactly two nonblocking rules'

for artifact in "$config" "$rules"; do
  if grep -Eiq '^[[:space:]]*(ignore|source|sources|exclude|exclusions)[[:space:]]*:' "$artifact"; then
    fail 'source exclusions are unsupported for these cross-language review instructions'
  fi

  if grep -Eiq '(-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|(^|[^[:alnum:]_])(api[_-]?key|access[_-]?token|auth[_-]?token|password|secret)[[:space:]]*[:=][[:space:]]*[^[:space:]#]+)' "$artifact"; then
    fail 'Sourcery configuration artifacts appear to contain an embedded secret'
  fi
done

if [[ "${SOURCERY_CONFIG_SKIP_REGRESSIONS:-0}" != 1 ]]; then
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  assert_rejected() {
    local fixture_config="$1"
    local fixture_rules="$2"
    local description="$3"
    if SOURCERY_CONFIG_PATH="$fixture_config" SOURCERY_RULES_PATH="$fixture_rules" \
      SOURCERY_CONFIG_SKIP_REGRESSIONS=1 bash "$0" >/dev/null 2>&1; then
      fail "accepted invalid Sourcery artifacts: $description"
    fi
  }

  sed '/Swift 6 and MainActor correctness/d' "$rules" > "$temp_dir/missing-main-actor.md"
  assert_rejected "$config" "$temp_dir/missing-main-actor.md" 'missing Swift blocking rule'

  cp "$config" "$temp_dir/unsupported-key.yaml"
  printf '%s\n' 'review_instructions: []' >> "$temp_dir/unsupported-key.yaml"
  assert_rejected "$temp_dir/unsupported-key.yaml" "$rules" 'unsupported review instructions key'

  cp "$rules" "$temp_dir/source-exclusion.md"
  printf '%s\n' 'ignore: [Vendor]' >> "$temp_dir/source-exclusion.md"
  assert_rejected "$config" "$temp_dir/source-exclusion.md" 'source exclusion'

  cp "$rules" "$temp_dir/embedded-secret.md"
  printf '%s\n' 'api_key: live-credential-value' >> "$temp_dir/embedded-secret.md"
  assert_rejected "$config" "$temp_dir/embedded-secret.md" 'embedded credential'
fi

printf 'PASS: Sourcery Dashboard review standards are auditable\n'
