#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_json="$(swift package --package-path "$package_root" dump-package)"

ruby -rjson -e '
  manifest = JSON.parse(ARGV.fetch(0))

  abort "expected Security package" unless manifest["name"] == "Security"
  abort "expected iOS 17" unless manifest["platforms"] == [
    { "options" => [], "platformName" => "ios", "version" => "17.0" }
  ]
  abort "expected Swift 6" unless manifest["swiftLanguageVersions"] == ["6"]
  abort "expected no package dependencies" unless manifest["dependencies"] == []

  products = manifest.fetch("products")
  abort "expected only the Security library" unless products.length == 1 &&
    products.first["name"] == "Security" && products.first["targets"] == ["Security"]

  targets = manifest.fetch("targets").to_h { |target| [target.fetch("name"), target] }
  abort "expected Security and SecurityTests targets" unless targets.keys.sort == ["Security", "SecurityTests"]
  abort "expected Security to be a regular target" unless targets.fetch("Security")["type"] == "regular"
  abort "expected Security to have no dependencies" unless targets.fetch("Security")["dependencies"] == []
  abort "expected SecurityTests to be a test target" unless targets.fetch("SecurityTests")["type"] == "test"
  abort "expected SecurityTests to depend only on Security" unless
    targets.fetch("SecurityTests")["dependencies"] == [{ "byName" => ["Security", nil] }]
' "$manifest_json"

printf 'PASS: Security package manifest contract\n'
