#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
config="${SONAR_CONFIG_PATH:-$repo_root/sonar-project.properties}"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

property_values() {
  local key="$1"
  awk -v wanted="$key" '
    {
      line = $0
      sub(/\r$/, "", line)
      sub(/^[[:space:]]+/, "", line)
      if (line == "" || line ~ /^[#!]/) next

      property = line
      sub(/[[:space:]=:].*$/, "", property)
      if (property != wanted) next

      value = substr(line, length(property) + 1)
      sub(/^[[:space:]]+/, "", value)
      if (value ~ /^[=:]/) value = substr(value, 2)
      sub(/^[[:space:]]+/, "", value)
      print value
    }
  ' "$config"
}

assert_property() {
  local key="$1"
  local expected="$2"
  local values
  local count
  values="$(property_values "$key")"
  count="$(property_values "$key" | awk 'END { print NR }')"
  [[ "$count" == 1 ]] || fail "$key must have exactly one assignment (found $count)"
  [[ "$values" == "$expected" ]] || fail "$key has invalid effective value: $values"
}

[[ -f "$config" ]] || fail "sonar-project.properties is absent"

if awk '
  {
    line = $0
    sub(/\r$/, "", line)
    sub(/^[[:space:]]+/, "", line)
    if (line != "" && line !~ /^[#!]/ && index(line, "\\") > 0) found = 1
  }
  END { exit(found ? 0 : 1) }
' "$config"; then
  fail 'property escapes and continuations are not allowed'
fi

assert_property 'sonar.projectKey' 'learning-superpower'
assert_property 'sonar.projectName' 'Learning Superpower Commerce'
assert_property 'sonar.sourceEncoding' 'UTF-8'
assert_property 'sonar.sources' 'Backend,Apps,Packages'
assert_property 'sonar.tests' 'Backend,Apps,Packages'
assert_property 'sonar.test.inclusions' 'Backend/**/*_test.go,Apps/**/Tests/**/*.swift,Apps/**/UITests/**/*.swift,Packages/**/Tests/**/*.swift'
assert_property 'sonar.go.coverage.reportPaths' 'Backend/coverage.out'
assert_property 'sonar.coverageReportPaths' 'Build/reports/swift-coverage.xml'
assert_property 'sonar.exclusions' '**/.build/**,**/Derived/**,**/*.xcodeproj/**,**/*.xcworkspace/**,Backend/**/*_test.go,Apps/**/Tests/**,Apps/**/UITests/**,Packages/**/Tests/**'

exclusions="$(property_values 'sonar.exclusions')"
for pattern in \
  '**/.build/**' \
  '**/Derived/**' \
  '**/*.xcodeproj/**' \
  '**/*.xcworkspace/**' \
  'Backend/**/*_test.go' \
  'Apps/**/Tests/**' \
  'Apps/**/UITests/**' \
  'Packages/**/Tests/**'; do
  case ",$exclusions," in
    *",$pattern,"*) ;;
    *) fail "missing exclusion: $pattern" ;;
  esac
done

if grep -Eiq '^[[:space:]]*sonar\.(host\.url|token|login)[[:space:]]*=' "$config"; then
  fail 'Sonar URL or credentials must not be embedded'
fi

if [[ "${SONAR_CONFIG_SKIP_REGRESSIONS:-0}" != 1 ]]; then
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  assert_rejected() {
    local fixture="$1"
    local description="$2"
    if SONAR_CONFIG_PATH="$fixture" SONAR_CONFIG_SKIP_REGRESSIONS=1 bash "$0" >/dev/null 2>&1; then
      fail "accepted invalid config: $description"
    fi
  }

  cp "$config" "$temp_dir/duplicate-project-key.properties"
  printf '%s\n' 'sonar.projectKey=attacker-override' >> "$temp_dir/duplicate-project-key.properties"
  assert_rejected "$temp_dir/duplicate-project-key.properties" 'duplicate project key override'

  cp "$config" "$temp_dir/duplicate-go-coverage.properties"
  printf '%s\n' 'sonar.go.coverage.reportPaths=other/coverage.out' >> "$temp_dir/duplicate-go-coverage.properties"
  assert_rejected "$temp_dir/duplicate-go-coverage.properties" 'duplicate Go coverage override'

  cp "$config" "$temp_dir/duplicate-swift-coverage.properties"
  printf '%s\n' 'sonar.coverageReportPaths=other/swift-coverage.xml' >> "$temp_dir/duplicate-swift-coverage.properties"
  assert_rejected "$temp_dir/duplicate-swift-coverage.properties" 'duplicate Swift coverage override'

  sed 's/^sonar\.exclusions=.*/sonar.exclusions=/' "$config" > "$temp_dir/empty-exclusions.properties"
  assert_rejected "$temp_dir/empty-exclusions.properties" 'empty exclusions'

  cp "$config" "$temp_dir/escaped-project-key.properties"
  printf '%s\n' 'sonar\.projectKey=attacker-override' >> "$temp_dir/escaped-project-key.properties"
  assert_rejected "$temp_dir/escaped-project-key.properties" 'escaped project key override'

  cp "$config" "$temp_dir/unicode-project-key.properties"
  printf '%s\n' 'sonar\u002eprojectKey=attacker-override' >> "$temp_dir/unicode-project-key.properties"
  assert_rejected "$temp_dir/unicode-project-key.properties" 'Unicode-escaped project key override'

  cp "$config" "$temp_dir/escaped-token.properties"
  printf '%s\n' 'sonar\.token=secret' >> "$temp_dir/escaped-token.properties"
  assert_rejected "$temp_dir/escaped-token.properties" 'escaped credential key'

  cp "$config" "$temp_dir/continued-property.properties"
  printf '%s\n' "sonar.projectKey\\" '=attacker-override' >> "$temp_dir/continued-property.properties"
  assert_rejected "$temp_dir/continued-property.properties" 'continued property'
fi

printf 'PASS: SonarQube project mapping is valid\n'
