#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
config="$repo_root/sonar-project.properties"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_property() {
  local expected="$1"
  grep -Fqx "$expected" "$config" || fail "missing property: $expected"
}

[[ -f "$config" ]] || fail "sonar-project.properties is absent"

assert_property 'sonar.projectKey=learning-superpower'
assert_property 'sonar.projectName=Learning Superpower Commerce'
assert_property 'sonar.sourceEncoding=UTF-8'
assert_property 'sonar.sources=Backend,Apps,Packages'
assert_property 'sonar.tests=Backend,Apps,Packages'
assert_property 'sonar.test.inclusions=Backend/**/*_test.go,Apps/**/Tests/**/*.swift,Apps/**/UITests/**/*.swift,Packages/**/Tests/**/*.swift'
assert_property 'sonar.go.coverage.reportPaths=Backend/coverage.out'
assert_property 'sonar.coverageReportPaths=Build/reports/swift-coverage.xml'

exclusions="$(sed -n 's/^sonar.exclusions=//p' "$config")"
[[ -n "$exclusions" ]] || fail 'missing sonar.exclusions'
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

printf 'PASS: SonarQube project mapping is valid\n'
