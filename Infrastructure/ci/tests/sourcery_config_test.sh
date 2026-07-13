#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
config="${SOURCERY_CONFIG_PATH:-$repo_root/.sourcery.yaml}"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$config" ]] || fail '.sourcery.yaml is absent'

ruby -e '
  require "yaml"
  config = YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], aliases: false)
  abort "configuration must be a YAML mapping" unless config.is_a?(Hash)
  supported = %w[version ignore rule_settings rules rule_tags metrics github clone_detection proxy]
  unknown = config.keys.map(&:to_s) - supported
  abort "unsupported top-level keys: #{unknown.join(", ")}" unless unknown.empty?
  abort "version must be schema version 1" unless config["version"] == "1"
' "$config" || fail 'configuration is not valid against the published Sourcery YAML shape'

for required in \
  'Swift 6' \
  'MainActor' \
  'Clean Architecture' \
  'MVVM-C' \
  'Factory' \
  'XCoordinator' \
  'Go' \
  'OWASP' \
  'regression test' \
  'file and line' \
  'actionable' \
  'correctness' \
  'security' \
  'data race' \
  'SwiftLint' \
  'gofmt'; do
  grep -Fq "$required" "$config" || fail "missing review guidance: $required"
done

if grep -Eiq '^[[:space:]]*(ignore|source|sources|exclude|exclusions)[[:space:]]*:' "$config"; then
  fail 'source exclusions are unsupported for these cross-language review instructions'
fi

if grep -Eiq '(-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|(^|[^[:alnum:]_])(api[_-]?key|access[_-]?token|auth[_-]?token|password|secret)[[:space:]]*[:=][[:space:]]*[^[:space:]#]+)' "$config"; then
  fail 'configuration appears to contain an embedded secret'
fi

if [[ "${SOURCERY_CONFIG_SKIP_REGRESSIONS:-0}" != 1 ]]; then
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  assert_rejected() {
    local fixture="$1"
    local description="$2"
    if SOURCERY_CONFIG_PATH="$fixture" SOURCERY_CONFIG_SKIP_REGRESSIONS=1 bash "$0" >/dev/null 2>&1; then
      fail "accepted invalid config: $description"
    fi
  }

  sed '/MainActor/d' "$config" > "$temp_dir/missing-main-actor.yaml"
  assert_rejected "$temp_dir/missing-main-actor.yaml" 'missing MainActor guidance'

  cp "$config" "$temp_dir/unsupported-key.yaml"
  printf '%s\n' 'review_instructions: []' >> "$temp_dir/unsupported-key.yaml"
  assert_rejected "$temp_dir/unsupported-key.yaml" 'unsupported review instructions key'

  cp "$config" "$temp_dir/source-exclusion.yaml"
  printf '%s\n' 'ignore: [Vendor]' >> "$temp_dir/source-exclusion.yaml"
  assert_rejected "$temp_dir/source-exclusion.yaml" 'source exclusion'

  cp "$config" "$temp_dir/embedded-secret.yaml"
  printf '%s\n' '# api_key: live-credential-value' >> "$temp_dir/embedded-secret.yaml"
  assert_rejected "$temp_dir/embedded-secret.yaml" 'embedded credential'
fi

printf 'PASS: Sourcery review standards are valid\n'
