#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <result-bundle.xcresult> <coverage.xml>" >&2
  exit 2
fi

result_bundle="$1"
report="$2"

if [[ -n "${XCCOV_BIN:-}" ]]; then
  xccov=("$XCCOV_BIN")
else
  xccov=(xcrun xccov)
fi

mkdir -p "$(dirname "$report")"
{
  printf '%s\n' '<coverage version="1">'
  "${xccov[@]}" view --archive --file-list "$result_bundle" |
  while IFS= read -r source_file; do
    escaped_file="$(printf '%s' "$source_file" | sed \
      -e 's/&/\&amp;/g' -e 's/"/\&quot;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
    printf '  <file path="%s">\n' "$escaped_file"
    "${xccov[@]}" view --archive --file "$source_file" "$result_bundle" |
      sed -E -n \
        -e 's/^[[:space:]]*([0-9]+): 0.*$/    <lineToCover lineNumber="\1" covered="false"\/>/p' \
        -e 's/^[[:space:]]*([0-9]+): [1-9][0-9]*.*$/    <lineToCover lineNumber="\1" covered="true"\/>/p'
    printf '%s\n' '  </file>'
  done
  printf '%s\n' '</coverage>'
} > "$report"

line_count="$(grep -c '<lineToCover ' "$report" || true)"
if [[ "$line_count" -eq 0 ]]; then
  echo "error: xccov produced no executable coverage lines" >&2
  exit 1
fi
