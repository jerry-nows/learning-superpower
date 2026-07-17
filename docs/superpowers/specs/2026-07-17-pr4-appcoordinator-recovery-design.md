# PR #4 AppCoordinator and UI Recovery Design

## Goal

Address the actionable Sourcery feedback without coupling the application
coordinator to a concrete login view controller, while adding a deterministic
UI test harness that does not use real credentials or network access. The
implementation deliberately avoids duplicating the future LoginFeature
contract (CR-048/CR-054) and production offline recovery (CR-102).

## Architecture

- `AppDelegate` and all UIKit lifecycle/coordinator types are `@MainActor`.
- `AppCoordinator` exposes a child-flow factory seam and retains the produced
  child flow, but does not introduce a second LoginFeature contract.
- The current placeholder remains behind that seam and will be replaced by
  CR-048/CR-054 when the Login SPM module is implemented.

## Failure/recovery behavior

When the UI test launches with `-ui-test-scenario networkFailure`, the current
test harness displays an accessible "No internet connection" message and a
Retry button. Tapping Retry transitions to an accessible "Connection
restored" message. Normal launches do not show either diagnostic state. This
is a harness-only placeholder; CR-102 owns the production recovery behavior.

The scenario is injected through launch arguments and is only test behavior;
no credentials, PII, backend, or external network are required.

## Test coverage

- Unit test verifies the coordinator starts a configured LoginFlow and retains
  the child-flow boundary while presenting its exported controller.
- Unit test verifies `@MainActor` lifecycle behavior through the existing
  main-actor test suites.
- UI test verifies the network failure message is visible and Retry restores
  the connection state.
- Existing launch smoke test remains unchanged for the normal path.

## Files expected to change

- `Apps/CommerceApp/Sources/AppDelegate.swift`
- `Apps/CommerceApp/Sources/Composition/AppContainer.swift`
- `Apps/CommerceApp/Sources/Navigation/AppCoordinator.swift`
- `Apps/CommerceApp/Sources/Navigation/LoginFlow.swift`
- `Apps/CommerceApp/Sources/SceneDelegate.swift`
- `Apps/CommerceApp/Tests/AppCoordinatorTests.swift`
- `Apps/CommerceApp/UITests/LaunchTests.swift`
