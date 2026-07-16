#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_json="$(swift package --package-path "$package_root" dump-package)"

ruby -rjson -e '
  manifest = JSON.parse(ARGV.fetch(0))
  abort "expected LoginFeature package" unless manifest["name"] == "LoginFeature"
  abort "expected iOS 17" unless manifest["platforms"] == [
    { "options" => [], "platformName" => "ios", "version" => "17.0" }
  ]
  abort "expected Swift 6" unless manifest["swiftLanguageVersions"] == ["6"]

  deps = manifest.fetch("dependencies").to_h { |d| [d.dig("fileSystem", 0, "identity"), d] }
  abort "expected local Core dependency" unless deps.key?("core")
  abort "expected local DesignSystem dependency" unless deps.key?("designsystem")
  abort "expected local Security dependency" unless deps.key?("security")
  abort "expected local Networking dependency" unless deps.key?("networking")

  products = manifest.fetch("products")
  abort "expected LoginFeature library" unless products.length == 1 &&
    products.first["name"] == "LoginFeature" &&
    products.first["type"] == { "library" => ["automatic"] } &&
    products.first["targets"] == ["LoginDomain", "LoginData", "LoginPresentation"]

  targets = manifest.fetch("targets").to_h { |target| [target.fetch("name"), target] }
  abort "expected Login targets and tests" unless targets.keys.sort == [
    "LoginData", "LoginDataTests", "LoginDomain", "LoginDomainTests",
    "LoginPresentation", "LoginPresentationTests"
  ]
  abort "LoginDomain must be dependency-free" unless targets["LoginDomain"]["dependencies"] == []
  abort "invalid LoginData dependencies" unless targets["LoginData"]["dependencies"] == [
    { "byName" => ["LoginDomain", nil] },
    { "product" => ["Networking", "Networking", nil, nil] },
    { "product" => ["SecurityKit", "Security", nil, nil] }
  ]
  abort "invalid LoginPresentation dependencies" unless targets["LoginPresentation"]["dependencies"] == [
    { "byName" => ["LoginDomain", nil] },
    { "product" => ["DesignSystem", "DesignSystem", nil, nil] }
  ]
' "$manifest_json"

printf 'PASS: LoginFeature package manifest contract\n'
