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
  'Reload the Dashboard' \
  'bash Infrastructure/ci/tests/sourcery_config_test.sh'; do
  grep -Fq "$required" "$rules" || fail "missing Dashboard rule artifact content: $required"
done

ruby - "$rules" <<'RUBY' || fail 'Dashboard rule sections do not match the review contract'
  rules = File.read(ARGV.fetch(0))
  sections = rules.scan(/^## Rule (\d+) — ([^\n]+)\n(.*?)(?=^## Rule |^## Dashboard setup)/m)

  expected = [
    ["1", "Swift 6 and MainActor correctness", "Apps/**/*.swift,Packages/**/*.swift", "Yes",
     ["Swift 6", "data races", "MainActor", "actor isolation", "Sendable", "Task lifetime", "file and line", "impact", "evidence", "concrete fix"]],
    ["2", "Clean Architecture, MVVM-C, Factory, and XCoordinator", "Apps/**/*.swift,Packages/**/*.swift", "No",
     ["architecture boundaries", "framework-independent", "MVVM-C", "Factory", "dependency direction", "XCoordinator", "navigation", "file-and-line evidence", "concrete fix"]],
    ["3", "Go, JWT, and OWASP", "Backend/**/*.go", "Yes",
     ["Go", "context propagation", "error handling", "concurrency safety", "resource lifetime", "JWT", "OWASP", "input validation", "injection", "sensitive-data exposure", "secret handling", "file and line", "concrete remediation"]],
    ["4", "Cross-repository correctness, security, and evidence", "**/*", "Yes",
     ["correctness", "security", "changed-code evidence", "file and line", "impact", "remediation", "formatting noise", "SwiftLint", "gofmt"]],
    ["5", "Regression tests, mocks, and UI recovery", "**/*Tests.swift,**/*_test.go,Apps/**/UITests/**/*.swift", "No",
     ["regression test", "behavior fix", "new behavior", "failure paths", "concurrency-sensitive", "mocks", "behavior fidelity", "UI tests", "deterministic state setup", "recovery", "failure evidence"]]
  ]

  abort "expected exactly five ordered rule sections" unless sections.length == expected.length

  sections.zip(expected).each do |(number, title, body), (wanted_number, wanted_title, wanted_path, wanted_blocking, topics)|
    abort "unexpected rule title or order: Rule #{number} — #{title}" unless [number, title] == [wanted_number, wanted_title]

    paths = body.scan(/^- Paths: `([^`]+)`$/)
    blocking = body.scan(/^- Blocking: (Yes|No)$/)
    instructions = body.scan(/^- Instructions: (.+)$/).flatten
    abort "Rule #{number} must have exact Paths glob #{wanted_path}" unless paths == [[wanted_path]]
    abort "Rule #{number} must have Blocking: #{wanted_blocking}" unless blocking == [[wanted_blocking]]
    abort "Rule #{number} must have exactly one Instructions field" unless instructions.length == 1

    missing = topics.reject { |topic| instructions.first.include?(topic) }
    abort "Rule #{number} instructions missing required topics: #{missing.join(", ")}" unless missing.empty?
  end
RUBY

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

  sed \
    -e '/## Rule 1/,/## Rule 2/{s/Blocking: Yes/Blocking: No/;}' \
    -e '/## Rule 2/,/## Rule 3/{s/Blocking: No/Blocking: Yes/;}' \
    "$rules" > "$temp_dir/swapped-blocking.md"
  assert_rejected "$config" "$temp_dir/swapped-blocking.md" 'swapped Rule 1 and Rule 2 blocking states'

  sed '/## Rule 2/,/## Rule 3/{s#Apps/\*\*/\*.swift,Packages/\*\*/\*.swift#Backend/**/*.go#;}' \
    "$rules" > "$temp_dir/wrong-rule-2-path.md"
  assert_rejected "$config" "$temp_dir/wrong-rule-2-path.md" 'wrong Rule 2 path glob'

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
