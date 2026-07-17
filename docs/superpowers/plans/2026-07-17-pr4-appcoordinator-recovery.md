# PR #4 AppCoordinator and UI Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** Harden UIKit main-actor isolation, add a replaceable AppCoordinator child-flow seam, and add a deterministic UI failure/recovery harness without duplicating future LoginFeature or offline-recovery CRs.

**Architecture:** `AppCoordinator` owns an internal child-flow protocol and factory seam; the current placeholder flow implements that seam and remains replaceable by CR-048/CR-054. A launch-argument scenario drives only placeholder UI diagnostics; CR-102 remains responsible for production recovery logic.

**Tech Stack:** Swift 6 strict concurrency, UIKit, XCoordinator, XCTest/Swift Testing, Tuist-generated Xcode project.

## Global Constraints

- UIKit lifecycle and navigation mutations are isolated to `@MainActor`.
- The coordinator must not instantiate a concrete login view controller in `prepareTransition`.
- UI tests use `-ui-test-scenario networkFailure`; no credentials, PII, backend, or external network.
- Do not create a second LoginFeature contract or implement CR-102 production recovery.

### Task 1: Main-actor lifecycle contract

**Files:**
- Modify: `Apps/CommerceApp/Sources/AppDelegate.swift`
- Modify: `Apps/CommerceApp/Tests/AppContainerTests.swift`

**Interfaces:** `AppDelegate` is `@MainActor`; existing `ApplicationCoordinating` remains `@MainActor`.

- [ ] Write a compile-time-focused test annotation/instantiation assertion in the existing `@MainActor` test suite.
- [ ] Run the focused CommerceApp test and confirm the current unannotated AppDelegate still exposes the concurrency diagnostic under Swift 6.
- [ ] Add `@MainActor` immediately above `@main` on `AppDelegate`.
- [ ] Run the focused test again and confirm it passes without a new concurrency error.
- [ ] Commit `fix(ios): isolate app delegate on main actor`.

### Task 2: Coordinator child-flow seam

**Files:**
- Modify: `Apps/CommerceApp/Sources/Navigation/AppCoordinator.swift`
- Modify: `Apps/CommerceApp/Tests/AppCoordinatorTests.swift`

**Interfaces:** Add internal `@MainActor protocol ApplicationChildFlow { var rootViewController: UIViewController { get } }`; `AppCoordinator.init(loginFlowFactory: @escaping @MainActor () -> any ApplicationChildFlow = { PlaceholderLoginFlow() })`.

- [ ] Add a failing test that injects a `ChildFlowSpy`, starts the coordinator, and asserts the spy’s exported controller is pushed.
- [ ] Run `AppCoordinatorTests` and verify it fails because the initializer/factory seam does not exist.
- [ ] Add `ApplicationChildFlow`, `ChildFlowFactory`, a retained `loginFlow`, and an injectable initializer.
- [ ] Change `prepareTransition` to call the factory once and push `loginFlow.rootViewController`; keep the placeholder flow as the default adapter.
- [ ] Run `AppCoordinatorTests` and the existing package/app tests; confirm all pass.
- [ ] Commit `refactor(ios): add coordinator child flow seam`.

### Task 3: Deterministic UI failure/recovery harness

**Files:**
- Modify: `Apps/CommerceApp/Sources/Navigation/AppCoordinator.swift`
- Modify: `Apps/CommerceApp/UITests/LaunchTests.swift`

**Interfaces:** Launch argument `-ui-test-scenario networkFailure`; accessibility identifiers `network-error-message`, `retry-connection`, `connection-restored-message`.

- [ ] Add a UI test that launches with the scenario argument, asserts the error message and Retry button, taps Retry, and asserts the recovered message.
- [ ] Run the focused UI test and verify it fails because the harness controls do not exist.
- [ ] Add scenario parsing to the placeholder flow only; render accessible error/retry/recovered controls without making network calls.
- [ ] Run the focused UI test and the normal launch smoke test; confirm both pass.
- [ ] Commit `test(ios): cover deterministic network recovery harness`.

### Task 4: Final verification

**Files:** None beyond prior tasks.

- [ ] Run `git diff --check`.
- [ ] Generate the CommerceApp workspace with the repository’s pinned Tuist command.
- [ ] Run CommerceApp unit tests, UI tests, and SwiftLint using the existing Makefile targets.
- [ ] Confirm the worktree is clean except for committed changes and record the exact test results.

