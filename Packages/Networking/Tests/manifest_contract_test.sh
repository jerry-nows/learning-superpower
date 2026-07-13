#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_json="$(swift package --package-path "$package_root" dump-package)"

ruby -rjson -e '
  manifest = JSON.parse(ARGV.fetch(0))

  abort "expected Networking package" unless manifest["name"] == "Networking"
  abort "expected iOS 17" unless manifest["platforms"] == [
    { "options" => [], "platformName" => "ios", "version" => "17.0" }
  ]
  abort "expected Swift 6" unless manifest["swiftLanguageVersions"] == ["6"]

  dependencies = manifest.fetch("dependencies")
  moya = dependencies.first&.fetch("sourceControl", nil)&.first
  abort "expected only Moya 15.x" unless dependencies.length == 1 &&
    moya&.fetch("identity", nil) == "moya" &&
    moya&.dig("location", "remote", 0, "urlString") == "https://github.com/Moya/Moya.git" &&
    moya&.dig("requirement", "range") == [
      { "lowerBound" => "15.0.0", "upperBound" => "16.0.0" }
    ]

  products = manifest.fetch("products")
  abort "expected only the Networking library" unless products.length == 1 &&
    products.first["name"] == "Networking" && products.first["targets"] == ["Networking"]

  targets = manifest.fetch("targets").to_h { |target| [target.fetch("name"), target] }
  abort "expected Networking and NetworkingTests targets" unless
    targets.keys.sort == ["Networking", "NetworkingTests"]

  networking = targets.fetch("Networking")
  abort "expected Networking to be a regular target" unless networking["type"] == "regular"
  abort "expected Networking to depend only on the Moya product" unless
    networking["dependencies"].length == 1 &&
    networking["dependencies"].first.fetch("product").first(2) == ["Moya", "Moya"]

  tests = targets.fetch("NetworkingTests")
  abort "expected NetworkingTests to be a test target" unless tests["type"] == "test"
  abort "expected NetworkingTests to depend only on Networking" unless
    tests["dependencies"] == [{ "byName" => ["Networking", nil] }]
' "$manifest_json"

printf 'PASS: Networking package manifest contract\n'
