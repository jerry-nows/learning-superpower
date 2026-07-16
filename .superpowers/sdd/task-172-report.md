# CR-172 Report

Status: complete

Implemented `ProductTarget` for the MenuFeature data layer with explicit Moya
targets for product lists, product detail, inventory, rating summary, comments,
and categories. List requests encode trimmed search, category, bounded page
size, cursor, filter values, and the allow-listed `ProductSort` raw value.
Product IDs are percent-encoded as path components, and independent detail
sections remain plain GET requests.

Added contract tests covering query encoding and bounds, endpoint paths,
authorization headers, and redaction of access tokens/query payloads from
diagnostics.

Verification:

- `swiftc -parse Packages/MenuFeature/Sources/MenuData/ProductTarget.swift` — pass.
- `swiftc -parse Packages/MenuFeature/Tests/MenuDataTests/ProductTargetTests.swift` — pass.
- `swift test --disable-sandbox` — blocked in this Linux environment because
  the existing `DesignSystem` target imports UIKit (`no such module 'UIKit'`).

The MenuFeature package manifest currently exposes only `MenuDomain`; wiring the
new `MenuData` target and test target is intentionally deferred to the next data
layer CR so this task remains limited to the target contract.
