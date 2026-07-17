# CR-175 Review Report

## Status

Implemented and committed as `969f825` (`feat(menu): resume product reads after connectivity`).

## Implementation

- Added `ConnectivityMonitor` in Core with an async `updates()` stream, initial-state emission, duplicate-state suppression, deterministic `update(_:)`, and optional `NWPathMonitor` integration.
- Added `ProductResumeCoordinator` with explicit read, mutation, and payment execution APIs. Only reads retry once after the monitor transitions back online; mutation and payment failures are returned immediately.
- Added deterministic Core connectivity tests and MenuData coordinator tests covering resume, mutation no-retry, and payment no-retry.

## Verification

- `swift test --package-path Packages/Core --disable-sandbox` — PASS (5 tests).
- `swiftc -parse Packages/MenuFeature/Sources/MenuData/ProductResumeCoordinator.swift` — PASS.
- `swiftc -parse Packages/MenuFeature/Tests/MenuDataTests/ProductResumeCoordinatorTests.swift` — PASS.
- `git diff --check` — PASS.
- Cancellation follow-up: `waitUntilOnline()` now races the connectivity stream with a cancellation-aware polling task; the new cancelled-read test verifies a task returns promptly without an online event.
- Follow-up verification: `swiftc -parse` passed for coordinator and tests; `swift test --package-path Packages/Core --disable-sandbox` passed all 5 Core tests. The MenuFeature test target remains unavailable until its UIKit-dependent package manifest is completed by the parallel presentation work.

## Concern

The current MenuFeature package manifest in this worktree does not yet expose the `MenuData` target on this task branch, and its DesignSystem dependency requires UIKit. Therefore the complete MenuFeature package test suite cannot run in the macOS-only environment until the parallel MenuFeature manifest/presentation work lands. The coordinator and test sources parse cleanly and are designed for the eventual MenuData target.
