# PR #4 AppCoordinator and UI Recovery Design

## Goal

Address the actionable Sourcery feedback without coupling the application
coordinator to a concrete login view controller, while adding a deterministic
UI failure/recovery test that does not use real credentials or network access.

## Architecture

- `AppDelegate` and all UIKit lifecycle/coordinator types are `@MainActor`.
- `LoginFlow` is a typed child-flow boundary owned by `AppCoordinator`.
- `LoginFlowConfiguration` carries launch-time scenario input; the flow exposes
  `LoginFlowResult` actions instead of exposing its screen implementation.
- `AppCoordinator.prepareTransition` creates and retains the child flow and
  pushes its exported view controller through XCoordinator. The coordinator
  does not instantiate a login view controller directly.
- The initial implementation remains a placeholder login flow, but the
  boundary is replaceable by the real Login SPM module without changing
  `AppCoordinator` routes.

## Failure/recovery behavior

When the UI test launches with `-ui-test-scenario networkFailure`, the login
flow displays an accessible "No internet connection" message and a Retry
button. Tapping Retry transitions to an accessible "Connection restored"
message. Normal launches do not show either diagnostic state.

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

