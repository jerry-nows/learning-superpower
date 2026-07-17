# CR-173 Review Report

## Status

Implemented the MenuFeature Moya remote data source.

## Scope

- Added `ProductRemoteDataSource` with async/await Moya requests.
- Added cancellation-safe request state with exactly-once continuation resumption.
- Added per-request ISO-8601 decoder and wire DTO mapping for snake-case API payloads.
- Added HTTP, transport, malformed payload, and cancellation error mapping.
- Added focused success, failure, malformed payload, and cancellation tests.

## Verification

`git diff --check` passes. Full Swift package tests are blocked until CR-172's
MenuData target is present in `Package.swift`; the current package manifest only
declares MenuDomain. Tests should be run with `swift test --disable-sandbox`
after that manifest change lands.

## Review fixes

- Replaced the invalid one-line multiline-string success fixture with a valid
  interpolated fixture.
- HTTP 408 now maps to `serviceUnavailable`; `.cancelled` remains reserved for
  client cancellation (`NSURLErrorCancelled` or task cancellation).
- `swiftc -parse Packages/MenuFeature/Sources/MenuData/ProductRemoteDataSource.swift` passes.
- `swiftc -parse Packages/MenuFeature/Tests/MenuDataTests/ProductRemoteDataSourceTests.swift` passes.
- `git diff --check` passes.

## Notes

The source is read-only and does not retry requests. Connectivity retry policy
belongs to CR-175. Product IDs are passed through `ProductTarget`, which owns
URL construction and escaping.
