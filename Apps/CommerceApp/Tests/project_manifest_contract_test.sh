#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_FILE="$ROOT_DIR/CommerceApp/Project.swift"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

grep -Fq '.local(path: "../../Packages/LoginFeature")' "$PROJECT_FILE" \
  || fail "LoginFeature local package is not declared"
grep -Fq '.local(path: "../../Packages/Security")' "$PROJECT_FILE" \
  || fail "Security local package is not declared"
grep -Fq '.local(path: "../../Packages/Networking")' "$PROJECT_FILE" \
  || fail "Networking local package is not declared"

for product in LoginFeature SecurityKit Networking; do
  grep -Fq ".package(product: \"$product\")" "$PROJECT_FILE" \
    || fail "$product is not linked to CommerceApp"
done

# The composition root links only public products; internal feature targets must
# remain hidden behind the package products.
if grep -Eq '\.target\(name: "(LoginDomain|LoginData|LoginPresentation|Security|Networking)"' "$PROJECT_FILE"; then
  fail "CommerceApp links an internal package target"
fi

printf 'PASS: CommerceApp package-link manifest contract\n'
