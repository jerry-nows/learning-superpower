#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
converter="$repo_root/Infrastructure/ci/xccov-to-sonarqube.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

cat > "$temp_dir/xccov" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  *--file-list*)
    printf '%s\n' '/workspace/Sources/Foo & Bar.swift'
    ;;
  *--file*)
    printf '%s\n' \
      '    10: 0: let uncovered = true' \
      '    11: 3: let covered = true'
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$temp_dir/xccov"

XCCOV_BIN="$temp_dir/xccov" "$converter" fixture.xcresult "$temp_dir/coverage.xml"

xmllint --noout "$temp_dir/coverage.xml"
grep -Fq '<file path="/workspace/Sources/Foo &amp; Bar.swift">' "$temp_dir/coverage.xml"
grep -Fq '<lineToCover lineNumber="10" covered="false"/>' "$temp_dir/coverage.xml"
grep -Fq '<lineToCover lineNumber="11" covered="true"/>' "$temp_dir/coverage.xml"

echo "PASS: xccov execution counts convert to SonarQube generic coverage XML"
