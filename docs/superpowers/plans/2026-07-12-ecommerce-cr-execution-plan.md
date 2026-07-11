# Ecommerce CR Execution Plan

Hands-on estimates assume prerequisites and dependencies are already green; code review and CI queue time are excluded. **Parallel: Yes** means the task may run beside another task after all listed dependencies are complete.

## Phase 1 — Repository and Local Infrastructure

### CR-001

**Objective:** Pin Go and tool versions.

**Files:** `.mise.toml`

**Steps:**

1. Add or update the focused test/contract that demonstrates pin go and tool versions.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `.mise.toml`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 5m

**Dependencies:** None

**Parallel:** Yes

**Definition of Done:** Tool installation resolves Go 1.26.5.

### CR-002

**Objective:** Define safe local defaults.

**Files:** `.env.example`

**Steps:**

1. Add or update the focused test/contract that demonstrates define safe local defaults.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `.env.example`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** None

**Parallel:** Yes

**Definition of Done:** All Compose variables exist with no real secrets.

### CR-003

**Objective:** Ignore generated secrets.

**Files:** `.gitignore`

**Steps:**

1. Add or update the focused test/contract that demonstrates ignore generated secrets.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `.gitignore`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 5m

**Dependencies:** CR-002

**Parallel:** No

**Definition of Done:** Environment files, certificates, keys and data are ignored.

### CR-004

**Objective:** Implement bootstrap preflight.

**Files:** `Infrastructure/scripts/check-tools.sh`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement bootstrap preflight.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Infrastructure/scripts/check-tools.sh`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-001

**Parallel:** Yes

**Definition of Done:** Missing tools produce actionable non-zero failures.

### CR-005

**Objective:** Test bootstrap preflight.

**Files:** `Infrastructure/tests/check-tools_test.sh`

**Steps:**

1. Add or update the focused test/contract that demonstrates test bootstrap preflight.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Infrastructure/tests/check-tools_test.sh`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-004

**Parallel:** No

**Definition of Done:** Success and missing-tool cases pass.

### CR-006

**Objective:** Declare backend module.

**Files:** `Backend/go.mod`

**Steps:**

1. Add or update the focused test/contract that demonstrates declare backend module.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/go.mod`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 5m

**Dependencies:** CR-001

**Parallel:** Yes

**Definition of Done:** Go module resolves and tidies cleanly.

### CR-007

**Objective:** Implement liveness handler.

**Files:** `Backend/internal/health/handler.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement liveness handler.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/health/handler.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-006

**Parallel:** No

**Definition of Done:** GET health returns stable JSON; other methods return 405.

### CR-008

**Objective:** Test liveness handler.

**Files:** `Backend/internal/health/handler_test.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates test liveness handler.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/health/handler_test.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-007

**Parallel:** No

**Definition of Done:** Handler tests pass under race detection.

### CR-009

**Objective:** Wire API process lifecycle.

**Files:** `Backend/cmd/api/main.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates wire api process lifecycle.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/cmd/api/main.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-008

**Parallel:** No

**Definition of Done:** Server applies timeouts and graceful shutdown.

### CR-010

**Objective:** Build non-root API image.

**Files:** `Backend/Dockerfile`

**Steps:**

1. Add or update the focused test/contract that demonstrates build non-root api image.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/Dockerfile`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-009

**Parallel:** No

**Definition of Done:** Image responds to health as UID 10001.

### CR-011

**Objective:** Define Compose topology.

**Files:** `Infrastructure/compose.yaml`

**Steps:**

1. Add or update the focused test/contract that demonstrates define compose topology.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Infrastructure/compose.yaml`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-002, CR-010

**Parallel:** No

**Definition of Done:** PostgreSQL, Redis, Kafka, API and Caddy validate with internal networking.

### CR-012

**Objective:** Test Compose contract.

**Files:** `Infrastructure/tests/compose_test.sh`

**Steps:**

1. Add or update the focused test/contract that demonstrates test compose contract.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Infrastructure/tests/compose_test.sh`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-011

**Parallel:** Yes

**Definition of Done:** Topology and published-port assertions pass.

### CR-013

**Objective:** Configure HTTPS reverse proxy.

**Files:** `Infrastructure/Caddyfile`

**Steps:**

1. Add or update the focused test/contract that demonstrates configure https reverse proxy.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Infrastructure/Caddyfile`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-011

**Parallel:** Yes

**Definition of Done:** Caddy routes trusted HTTPS to API with security headers.

### CR-014

**Objective:** Generate local certificates.

**Files:** `Infrastructure/scripts/create-certs.sh`

**Steps:**

1. Add or update the focused test/contract that demonstrates generate local certificates.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Infrastructure/scripts/create-certs.sh`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-003

**Parallel:** No

**Definition of Done:** mkcert produces host/LAN SANs and mode-600 private key.

### CR-015

**Objective:** Test certificate generation.

**Files:** `Infrastructure/tests/certs_test.sh`

**Steps:**

1. Add or update the focused test/contract that demonstrates test certificate generation.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Infrastructure/tests/certs_test.sh`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-014

**Parallel:** No

**Definition of Done:** Mocked generator test passes without real secrets.

### CR-016

**Objective:** Implement infrastructure smoke check.

**Files:** `Infrastructure/scripts/smoke.sh`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement infrastructure smoke check.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Infrastructure/scripts/smoke.sh`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-011, CR-013, CR-014

**Parallel:** No

**Definition of Done:** HTTPS, PostgreSQL, Redis and Kafka checks emit stable success.

### CR-017

**Objective:** Add foundation Make targets.

**Files:** `Makefile`

**Steps:**

1. Add or update the focused test/contract that demonstrates add foundation make targets.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Makefile`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-004, CR-016

**Parallel:** No

**Definition of Done:** Bootstrap, certs, lifecycle, tests and smoke targets work.

### CR-018

**Objective:** Document local setup.

**Files:** `docs/development/local-setup.md`

**Steps:**

1. Add or update the focused test/contract that demonstrates document local setup.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `docs/development/local-setup.md`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-017

**Parallel:** No

**Definition of Done:** A new developer can trust CA and reach health from Simulator/device.

## Phase 2 — iOS Workspace and Shared Platform

### CR-019

**Objective:** Pin Tuist configuration.

**Files:** `Tuist.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates pin tuist configuration.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Tuist.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 5m

**Dependencies:** CR-018

**Parallel:** Yes

**Definition of Done:** Tuist version is reproducible.

### CR-020

**Objective:** Configure SwiftLint.

**Files:** `.swiftlint.yml`

**Steps:**

1. Add or update the focused test/contract that demonstrates configure swiftlint.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `.swiftlint.yml`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-018

**Parallel:** Yes

**Definition of Done:** Strict rules load and exclude generated paths.

### CR-021

**Objective:** Declare Tuist workspace.

**Files:** `Workspace.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates declare tuist workspace.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Workspace.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-019

**Parallel:** No

**Definition of Done:** Workspace discovers app and packages.

### CR-022

**Objective:** Declare Commerce app targets.

**Files:** `Apps/CommerceApp/Project.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates declare commerce app targets.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/Project.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-021

**Parallel:** Yes

**Definition of Done:** iOS 17 app, unit and UI targets generate without signing.

### CR-023

**Objective:** Configure scene and ATS.

**Files:** `Apps/CommerceApp/Resources/Info.plist`

**Steps:**

1. Add or update the focused test/contract that demonstrates configure scene and ats.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/Resources/Info.plist`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-022

**Parallel:** Yes

**Definition of Done:** Scene metadata is valid and ATS has no arbitrary-load exception.

### CR-024

**Objective:** Implement app delegate.

**Files:** `Apps/CommerceApp/Sources/AppDelegate.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement app delegate.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/Sources/AppDelegate.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 5m

**Dependencies:** CR-022

**Parallel:** Yes

**Definition of Done:** App delegate returns scene configuration.

### CR-025

**Objective:** Implement scene delegate.

**Files:** `Apps/CommerceApp/Sources/SceneDelegate.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement scene delegate.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/Sources/SceneDelegate.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-024

**Parallel:** No

**Definition of Done:** Window retains root coordinator.

### CR-026

**Objective:** Declare Core package.

**Files:** `Packages/Core/Package.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates declare core package.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/Core/Package.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-021

**Parallel:** Yes

**Definition of Done:** Core resolves independently in Swift 6 mode.

### CR-027

**Objective:** Implement typed identifier.

**Files:** `Packages/Core/Sources/Core/Identifier.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement typed identifier.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/Core/Sources/Core/Identifier.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-026

**Parallel:** No

**Definition of Done:** Sendable identifiers prevent entity-tag mixing.

### CR-028

**Objective:** Test typed identifier.

**Files:** `Packages/Core/Tests/CoreTests/IdentifierTests.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates test typed identifier.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/Core/Tests/CoreTests/IdentifierTests.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-027

**Parallel:** No

**Definition of Done:** Codable, hash and raw-value tests pass.

### CR-029

**Objective:** Declare DesignSystem package.

**Files:** `Packages/DesignSystem/Package.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates declare designsystem package.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/DesignSystem/Package.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-021

**Parallel:** Yes

**Definition of Done:** UIKit design package and tests resolve.

### CR-030

**Objective:** Implement semantic colors.

**Files:** `Packages/DesignSystem/Sources/DesignSystem/ColorToken.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement semantic colors.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/DesignSystem/Sources/DesignSystem/ColorToken.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-029

**Parallel:** Yes

**Definition of Done:** Light and Dark semantic palettes resolve.

### CR-031

**Objective:** Implement scalable typography.

**Files:** `Packages/DesignSystem/Sources/DesignSystem/Typography.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement scalable typography.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/DesignSystem/Sources/DesignSystem/Typography.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-029

**Parallel:** Yes

**Definition of Done:** Editorial fonts scale with Dynamic Type.

### CR-032

**Objective:** Implement skeleton component.

**Files:** `Packages/DesignSystem/Sources/DesignSystem/SkeletonView.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement skeleton component.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/DesignSystem/Sources/DesignSystem/SkeletonView.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-030, CR-031

**Parallel:** No

**Definition of Done:** Skeleton respects Reduce Motion.

### CR-033

**Objective:** Implement connectivity banner.

**Files:** `Packages/DesignSystem/Sources/DesignSystem/ConnectivityBanner.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement connectivity banner.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/DesignSystem/Sources/DesignSystem/ConnectivityBanner.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-030

**Parallel:** No

**Definition of Done:** Offline/restored variants are accessible.

### CR-034

**Objective:** Register Factory composition.

**Files:** `Apps/CommerceApp/Sources/Composition/AppContainer.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates register factory composition.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/Sources/Composition/AppContainer.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-025, CR-028

**Parallel:** No

**Definition of Done:** Dependencies resolve only at composition boundaries.

### CR-035

**Objective:** Implement root coordinator.

**Files:** `Apps/CommerceApp/Sources/Navigation/AppCoordinator.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement root coordinator.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/Sources/Navigation/AppCoordinator.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-034

**Parallel:** No

**Definition of Done:** Root XCoordinator owns child-flow lifecycle.

### CR-036

**Objective:** Add workspace commands.

**Files:** `Makefile`

**Steps:**

1. Add or update the focused test/contract that demonstrates add workspace commands.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Makefile`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-022, CR-035

**Parallel:** No

**Definition of Done:** Generate, package test and unsigned build targets pass.

## Phase 3 — Authentication End to End

### CR-037

**Objective:** Create auth migration.

**Files:** `Backend/migrations/000001_auth.sql`

**Steps:**

1. Add or update the focused test/contract that demonstrates create auth migration.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/migrations/000001_auth.sql`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-011

**Parallel:** No

**Definition of Done:** Users and refresh-family schema migrates up/down.

### CR-038

**Objective:** Define auth domain models.

**Files:** `Backend/internal/auth/model.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates define auth domain models.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/auth/model.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-037

**Parallel:** No

**Definition of Done:** Models exclude password hash from transport.

### CR-039

**Objective:** Implement Argon2id hasher.

**Files:** `Backend/internal/auth/password.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement argon2id hasher.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/auth/password.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-038

**Parallel:** Yes

**Definition of Done:** Salted hash verifies in constant time.

### CR-040

**Objective:** Test password hasher.

**Files:** `Backend/internal/auth/password_test.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates test password hasher.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/auth/password_test.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-039

**Parallel:** No

**Definition of Done:** Valid, invalid and malformed cases pass.

### CR-041

**Objective:** Implement JWT issuer.

**Files:** `Backend/internal/auth/jwt.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement jwt issuer.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/auth/jwt.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-038

**Parallel:** Yes

**Definition of Done:** Access token has deterministic 60-second lifetime.

### CR-042

**Objective:** Test JWT issuer.

**Files:** `Backend/internal/auth/jwt_test.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates test jwt issuer.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/auth/jwt_test.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-041

**Parallel:** No

**Definition of Done:** Expiry, signature and claim tests pass without sleeps.

### CR-043

**Objective:** Implement opaque refresh tokens.

**Files:** `Backend/internal/auth/refresh_token.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement opaque refresh tokens.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/auth/refresh_token.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-038

**Parallel:** Yes

**Definition of Done:** 256-bit raw token and storage hash are separated.

### CR-044

**Objective:** Implement auth service.

**Files:** `Backend/internal/auth/service.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement auth service.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/auth/service.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-040, CR-042, CR-043

**Parallel:** No

**Definition of Done:** Login, rotation, reuse revocation and logout return typed errors.

### CR-045

**Objective:** Test auth lifecycle.

**Files:** `Backend/internal/auth/service_test.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates test auth lifecycle.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/auth/service_test.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-044

**Parallel:** No

**Definition of Done:** Rotation and family-reuse scenarios pass.

### CR-046

**Objective:** Implement auth HTTP handlers.

**Files:** `Backend/internal/auth/handler.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement auth http handlers.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/auth/handler.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-045

**Parallel:** No

**Definition of Done:** Auth endpoints return stable AUTH error codes.

### CR-047

**Objective:** Declare LoginFeature package.

**Files:** `Packages/LoginFeature/Package.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates declare loginfeature package.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/LoginFeature/Package.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-021

**Parallel:** No

**Definition of Done:** Feature layers resolve without other feature imports.

### CR-048

**Objective:** Define login flow contract.

**Files:** `Packages/LoginFeature/Sources/LoginDomain/LoginFlowContract.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates define login flow contract.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/LoginFeature/Sources/LoginDomain/LoginFlowContract.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-047

**Parallel:** Yes

**Definition of Done:** Public input/config/result are immutable Sendable values.

### CR-049

**Objective:** Implement Keychain token store.

**Files:** `Packages/Security/Sources/Security/KeychainTokenStore.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement keychain token store.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/Security/Sources/Security/KeychainTokenStore.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-047

**Parallel:** Yes

**Definition of Done:** Tokens use ThisDeviceOnly and atomic replace/clear.

### CR-050

**Objective:** Implement Face ID gate.

**Files:** `Packages/Security/Sources/Security/BiometricGate.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement face id gate.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/Security/Sources/Security/BiometricGate.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-047

**Parallel:** Yes

**Definition of Done:** Success, cancel and unavailable outcomes are typed.

### CR-051

**Objective:** Implement refresh single-flight actor.

**Files:** `Packages/Networking/Sources/Networking/AuthRefreshActor.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement refresh single-flight actor.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/Networking/Sources/Networking/AuthRefreshActor.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-049

**Parallel:** No

**Definition of Done:** Concurrent 401s trigger one refresh and one retry.

### CR-052

**Objective:** Implement login view model.

**Files:** `Packages/LoginFeature/Sources/LoginPresentation/LoginViewModel.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement login view model.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/LoginFeature/Sources/LoginPresentation/LoginViewModel.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-046, CR-048, CR-049, CR-050, CR-051

**Parallel:** No

**Definition of Done:** MainActor state covers validation, loading, success and localized errors.

### CR-053

**Objective:** Implement login controller.

**Files:** `Packages/LoginFeature/Sources/LoginPresentation/LoginViewController.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement login controller.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/LoginFeature/Sources/LoginPresentation/LoginViewController.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-052

**Parallel:** No

**Definition of Done:** Accessible VI/EN Light/Dark login form works.

### CR-054

**Objective:** Implement login coordinator.

**Files:** `Packages/LoginFeature/Sources/LoginPresentation/LoginCoordinator.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement login coordinator.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/LoginFeature/Sources/LoginPresentation/LoginCoordinator.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-035, CR-048, CR-050, CR-053

**Parallel:** No

**Definition of Done:** Flow emits only LoginResult to app root.

## Phase 4 — Catalog, Search and Cache

### CR-055

**Objective:** Create catalog migration.

**Files:** `Backend/migrations/000002_catalog.sql`

**Steps:**

1. Add or update the focused test/contract that demonstrates create catalog migration.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/migrations/000002_catalog.sql`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-037

**Parallel:** No

**Definition of Done:** Categories, products and inventory migrate with indexes.

### CR-056

**Objective:** Create lifestyle seeds.

**Files:** `Backend/seeds/catalog.sql`

**Steps:**

1. Add or update the focused test/contract that demonstrates create lifestyle seeds.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/seeds/catalog.sql`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-055

**Parallel:** Yes

**Definition of Done:** Idempotent multi-category seed loads.

### CR-057

**Objective:** Define catalog query.

**Files:** `Backend/internal/catalog/query.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates define catalog query.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/catalog/query.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-055

**Parallel:** Yes

**Definition of Done:** Cursor, search, filters and sort validate deterministically.

### CR-058

**Objective:** Implement catalog repository.

**Files:** `Backend/internal/catalog/repository.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement catalog repository.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/catalog/repository.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-057

**Parallel:** No

**Definition of Done:** Parameterized stable-cursor query returns page.

### CR-059

**Objective:** Test catalog repository.

**Files:** `Backend/internal/catalog/repository_test.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates test catalog repository.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/catalog/repository_test.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-058

**Parallel:** No

**Definition of Done:** Testcontainer covers paging, filter and sort.

### CR-060

**Objective:** Implement catalog handlers.

**Files:** `Backend/internal/catalog/handler.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement catalog handlers.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/catalog/handler.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-059

**Parallel:** No

**Definition of Done:** Products/categories endpoints return typed errors.

### CR-061

**Objective:** Declare CatalogFeature package.

**Files:** `Packages/CatalogFeature/Package.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates declare catalogfeature package.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CatalogFeature/Package.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-021

**Parallel:** No

**Definition of Done:** Catalog layers resolve without LoginFeature.

### CR-062

**Objective:** Define catalog domain models.

**Files:** `Packages/CatalogFeature/Sources/CatalogDomain/CatalogModels.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates define catalog domain models.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CatalogFeature/Sources/CatalogDomain/CatalogModels.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-061

**Parallel:** No

**Definition of Done:** Product, Category, Query and Page stay persistence-free.

### CR-063

**Objective:** Implement Moya catalog target.

**Files:** `Packages/CatalogFeature/Sources/CatalogData/CatalogTarget.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement moya catalog target.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CatalogFeature/Sources/CatalogData/CatalogTarget.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-060, CR-062

**Parallel:** No

**Definition of Done:** Request paths and normalized query snapshots match API.

### CR-064

**Objective:** Create Core Data catalog model.

**Files:** `Packages/Persistence/Sources/Persistence/CommerceModel.xcdatamodeld`

**Steps:**

1. Add or update the focused test/contract that demonstrates create core data catalog model.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/Persistence/Sources/Persistence/CommerceModel.xcdatamodeld`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-062

**Parallel:** No

**Definition of Done:** Versioned cache entities load in memory.

### CR-065

**Objective:** Implement catalog cache.

**Files:** `Packages/CatalogFeature/Sources/CatalogData/CoreDataCatalogCache.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement catalog cache.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CatalogFeature/Sources/CatalogData/CoreDataCatalogCache.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-064

**Parallel:** No

**Definition of Done:** Query pages persist and first page replaces atomically.

### CR-066

**Objective:** Implement catalog view model.

**Files:** `Packages/CatalogFeature/Sources/CatalogPresentation/CatalogViewModel.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement catalog view model.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CatalogFeature/Sources/CatalogPresentation/CatalogViewModel.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-063, CR-065

**Parallel:** No

**Definition of Done:** Cache-first refresh, 350ms search and paging states work.

### CR-067

**Objective:** Implement catalog controller.

**Files:** `Packages/CatalogFeature/Sources/CatalogPresentation/CatalogViewController.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement catalog controller.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CatalogFeature/Sources/CatalogPresentation/CatalogViewController.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-066

**Parallel:** No

**Definition of Done:** Grid, refresh, search, category, filter, sort and paging are accessible.

### CR-068

**Objective:** Implement catalog coordinator.

**Files:** `Packages/CatalogFeature/Sources/CatalogPresentation/CatalogCoordinator.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement catalog coordinator.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CatalogFeature/Sources/CatalogPresentation/CatalogCoordinator.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-035, CR-067

**Parallel:** No

**Definition of Done:** Host receives openProduct, openCart and logout actions.

## Phase 5 — Product Detail and Connectivity

### CR-069

**Objective:** Create reviews migration.

**Files:** `Backend/migrations/000003_reviews.sql`

**Steps:**

1. Add or update the focused test/contract that demonstrates create reviews migration.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/migrations/000003_reviews.sql`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-055

**Parallel:** No

**Definition of Done:** Reviews/comments schema migrates with indexes.

### CR-070

**Objective:** Implement detail repository.

**Files:** `Backend/internal/catalog/detail_repository.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement detail repository.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/catalog/detail_repository.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-069

**Parallel:** No

**Definition of Done:** Product, inventory, rating and comments queries remain independent.

### CR-071

**Objective:** Implement detail handlers.

**Files:** `Backend/internal/catalog/detail_handler.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement detail handlers.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/catalog/detail_handler.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-070

**Parallel:** No

**Definition of Done:** Four section endpoints fail independently with typed errors.

### CR-072

**Objective:** Define section state.

**Files:** `Packages/CatalogFeature/Sources/CatalogDomain/ProductDetailState.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates define section state.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CatalogFeature/Sources/CatalogDomain/ProductDetailState.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-062

**Parallel:** No

**Definition of Done:** Each section has independent loading/content/failure state.

### CR-073

**Objective:** Implement path monitor.

**Files:** `Packages/Connectivity/Sources/Connectivity/ConnectivityMonitor.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement path monitor.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/Connectivity/Sources/Connectivity/ConnectivityMonitor.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-021

**Parallel:** No

**Definition of Done:** Deduplicated online/offline async stream works.

### CR-074

**Objective:** Implement pending registry.

**Files:** `Packages/Connectivity/Sources/Connectivity/PendingRequestRegistry.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement pending registry.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/Connectivity/Sources/Connectivity/PendingRequestRegistry.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-073

**Parallel:** No

**Definition of Done:** Only live, retryable and deduplicated work remains.

### CR-075

**Objective:** Implement retry policy.

**Files:** `Packages/Connectivity/Sources/Connectivity/RetryPolicy.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement retry policy.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/Connectivity/Sources/Connectivity/RetryPolicy.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-074

**Parallel:** No

**Definition of Done:** Bounded jitter excludes auth, pinning and orders.

### CR-076

**Objective:** Implement detail view model.

**Files:** `Packages/CatalogFeature/Sources/CatalogPresentation/ProductDetailViewModel.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement detail view model.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CatalogFeature/Sources/CatalogPresentation/ProductDetailViewModel.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-071, CR-072, CR-074, CR-075

**Parallel:** No

**Definition of Done:** Task group progressively publishes and lifecycle cancellation cleans registry.

### CR-077

**Objective:** Implement detail controller.

**Files:** `Packages/CatalogFeature/Sources/CatalogPresentation/ProductDetailViewController.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement detail controller.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CatalogFeature/Sources/CatalogPresentation/ProductDetailViewController.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-076

**Parallel:** No

**Definition of Done:** Compositional sections replace matching skeletons independently.

### CR-078

**Objective:** Present global connectivity state.

**Files:** `Apps/CommerceApp/Sources/Composition/ConnectivityPresenter.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates present global connectivity state.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/Sources/Composition/ConnectivityPresenter.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-033, CR-073

**Parallel:** No

**Definition of Done:** Offline/restored banner never blocks cached content.

## Phase 6 — Cart, COD Orders and Kafka

### CR-079

**Objective:** Create order/outbox migration.

**Files:** `Backend/migrations/000004_orders.sql`

**Steps:**

1. Add or update the focused test/contract that demonstrates create order/outbox migration.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/migrations/000004_orders.sql`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-055

**Parallel:** No

**Definition of Done:** Orders, items, idempotency, reservations and outbox migrate.

### CR-080

**Objective:** Define order models.

**Files:** `Backend/internal/order/model.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates define order models.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/order/model.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-079

**Parallel:** No

**Definition of Done:** Quote, COD order and immutable item snapshot are storage-free.

### CR-081

**Objective:** Implement quote service.

**Files:** `Backend/internal/order/quote_service.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement quote service.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/order/quote_service.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-080

**Parallel:** No

**Definition of Done:** Price and stock changes produce explicit quote result.

### CR-082

**Objective:** Implement transactional order repository.

**Files:** `Backend/internal/order/repository.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement transactional order repository.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/order/repository.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-079, CR-080

**Parallel:** No

**Definition of Done:** Inventory lock, order, items and outbox commit atomically.

### CR-083

**Objective:** Test idempotent transaction.

**Files:** `Backend/internal/order/repository_test.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates test idempotent transaction.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/order/repository_test.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-082

**Parallel:** Yes

**Definition of Done:** Concurrent same-key requests create one order/event.

### CR-084

**Objective:** Implement order handlers.

**Files:** `Backend/internal/order/handler.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement order handlers.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/order/handler.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-081, CR-082

**Parallel:** No

**Definition of Done:** Quote, create and by-key lookup expose typed ORDER errors.

### CR-085

**Objective:** Implement outbox relay.

**Files:** `Backend/internal/outbox/relay.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement outbox relay.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/outbox/relay.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-082

**Parallel:** Yes

**Definition of Done:** Rows publish after commit and survive restart.

### CR-086

**Objective:** Implement idempotent Kafka consumer.

**Files:** `Backend/internal/eventconsumer/consumer.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement idempotent kafka consumer.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/eventconsumer/consumer.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-085

**Parallel:** No

**Definition of Done:** Duplicate event IDs create one business effect; retry/DLT is bounded.

### CR-087

**Objective:** Declare CartCheckoutFeature package.

**Files:** `Packages/CartCheckoutFeature/Package.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates declare cartcheckoutfeature package.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CartCheckoutFeature/Package.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-021

**Parallel:** No

**Definition of Done:** Feature resolves with shared packages only.

### CR-088

**Objective:** Define cart/checkout contracts.

**Files:** `Packages/CartCheckoutFeature/Sources/CartDomain/CartModels.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates define cart/checkout contracts.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CartCheckoutFeature/Sources/CartDomain/CartModels.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-087

**Parallel:** No

**Definition of Done:** Per-user cart and checkout result types are Sendable.

### CR-089

**Objective:** Implement Core Data cart store.

**Files:** `Packages/CartCheckoutFeature/Sources/CartData/CoreDataCartStore.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement core data cart store.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CartCheckoutFeature/Sources/CartData/CoreDataCartStore.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-064, CR-088

**Parallel:** No

**Definition of Done:** Cart survives relaunch and isolates users.

### CR-090

**Objective:** Implement cart view model.

**Files:** `Packages/CartCheckoutFeature/Sources/CartPresentation/CartViewModel.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement cart view model.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CartCheckoutFeature/Sources/CartPresentation/CartViewModel.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-089

**Parallel:** No

**Definition of Done:** Quantity/remove and quote changes publish correctly.

### CR-091

**Objective:** Implement cart controller.

**Files:** `Packages/CartCheckoutFeature/Sources/CartPresentation/CartViewController.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement cart controller.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CartCheckoutFeature/Sources/CartPresentation/CartViewController.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-090

**Parallel:** No

**Definition of Done:** Accessible item/total UI preserves unaffected rows.

### CR-092

**Objective:** Implement checkout view model.

**Files:** `Packages/CartCheckoutFeature/Sources/CheckoutPresentation/CheckoutViewModel.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement checkout view model.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CartCheckoutFeature/Sources/CheckoutPresentation/CheckoutViewModel.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-084, CR-088

**Parallel:** No

**Definition of Done:** Validation and stable idempotency never auto-resubmit.

### CR-093

**Objective:** Implement checkout controller.

**Files:** `Packages/CartCheckoutFeature/Sources/CheckoutPresentation/CheckoutViewController.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement checkout controller.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CartCheckoutFeature/Sources/CheckoutPresentation/CheckoutViewController.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-092

**Parallel:** No

**Definition of Done:** Localized COD form exposes submit and status check.

### CR-094

**Objective:** Implement cart/checkout coordinator.

**Files:** `Packages/CartCheckoutFeature/Sources/CheckoutPresentation/CartCheckoutCoordinator.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement cart/checkout coordinator.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/CartCheckoutFeature/Sources/CheckoutPresentation/CartCheckoutCoordinator.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-091, CR-093

**Parallel:** No

**Definition of Done:** Flow emits completed order or cancellation only.

### CR-095

**Objective:** Handle checkout result.

**Files:** `Apps/CommerceApp/Sources/Navigation/AppCoordinator.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates handle checkout result.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/Sources/Navigation/AppCoordinator.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 10m

**Dependencies:** CR-068, CR-094

**Parallel:** No

**Definition of Done:** Success clears cart, returns existing catalog root and notifies.

## Phase 7 — Contracts, Hardening, Tests and CI

### CR-096

**Objective:** Write OpenAPI contract.

**Files:** `Backend/openapi/openapi.yaml`

**Steps:**

1. Add or update the focused test/contract that demonstrates write openapi contract.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/openapi/openapi.yaml`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-046, CR-060, CR-071, CR-084

**Parallel:** No

**Definition of Done:** Every v1 route and typed error validates.

### CR-097

**Objective:** Add sanitized API fixtures.

**Files:** `Packages/TestSupport/Resources/API/fixtures.json`

**Steps:**

1. Add or update the focused test/contract that demonstrates add sanitized api fixtures.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/TestSupport/Resources/API/fixtures.json`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-096

**Parallel:** No

**Definition of Done:** Fixtures validate and contain no PII/secrets.

### CR-098

**Objective:** Implement SPKI verifier.

**Files:** `Packages/Networking/Sources/Networking/SPKIPinVerifier.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement spki verifier.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/Networking/Sources/Networking/SPKIPinVerifier.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-013, CR-023

**Parallel:** No

**Definition of Done:** Primary/backup pins pass; mismatch fails closed.

### CR-099

**Objective:** Test refresh concurrency.

**Files:** `Packages/Networking/Tests/NetworkingTests/AuthRefreshActorTests.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates test refresh concurrency.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/Networking/Tests/NetworkingTests/AuthRefreshActorTests.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-051

**Parallel:** No

**Definition of Done:** Repeated concurrent test proves one refresh.

### CR-100

**Objective:** Add login UI journey.

**Files:** `Apps/CommerceApp/UITests/LoginJourneyTests.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates add login ui journey.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/UITests/LoginJourneyTests.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-054

**Parallel:** No

**Definition of Done:** Invalid, seeded and biometric fallback journeys pass.

### CR-101

**Objective:** Add catalog UI journey.

**Files:** `Apps/CommerceApp/UITests/CatalogJourneyTests.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates add catalog ui journey.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/UITests/CatalogJourneyTests.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-068

**Parallel:** No

**Definition of Done:** Search/filter/paging/detail journey passes.

### CR-102

**Objective:** Add offline recovery journey.

**Files:** `Apps/CommerceApp/UITests/OfflineRecoveryTests.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates add offline recovery journey.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/UITests/OfflineRecoveryTests.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-078

**Parallel:** No

**Definition of Done:** Only unfinished safe sections resume.

### CR-103

**Objective:** Add checkout UI journey.

**Files:** `Apps/CommerceApp/UITests/CheckoutJourneyTests.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates add checkout ui journey.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/UITests/CheckoutJourneyTests.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-095

**Parallel:** No

**Definition of Done:** Validation, success and ambiguous failure pass.

### CR-104

**Objective:** Add Editorial snapshots.

**Files:** `Packages/DesignSystem/Tests/DesignSystemTests/EditorialSnapshots.swift`

**Steps:**

1. Add or update the focused test/contract that demonstrates add editorial snapshots.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Packages/DesignSystem/Tests/DesignSystemTests/EditorialSnapshots.swift`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-030, CR-031, CR-032, CR-033

**Parallel:** No

**Definition of Done:** Light/Dark, VI/EN and Dynamic Type snapshots are stable.

### CR-105

**Objective:** Complete localization catalog.

**Files:** `Apps/CommerceApp/Resources/Localizable.xcstrings`

**Steps:**

1. Add or update the focused test/contract that demonstrates complete localization catalog.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Apps/CommerceApp/Resources/Localizable.xcstrings`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-053, CR-067, CR-077, CR-091, CR-093

**Parallel:** No

**Definition of Done:** No user-facing or accessibility key is untranslated.

### CR-106

**Objective:** Implement HTTP security middleware.

**Files:** `Backend/internal/platform/httpsecurity/middleware.go`

**Steps:**

1. Add or update the focused test/contract that demonstrates implement http security middleware.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Backend/internal/platform/httpsecurity/middleware.go`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-046

**Parallel:** No

**Definition of Done:** Limits, headers, trace IDs, redaction and rate interface pass tests.

### CR-107

**Objective:** Add security workflow.

**Files:** `.github/workflows/security.yml`

**Steps:**

1. Add or update the focused test/contract that demonstrates add security workflow.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `.github/workflows/security.yml`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-010, CR-022

**Parallel:** No

**Definition of Done:** CodeQL, dependency review, Gitleaks, Trivy and SBOM run.

### CR-108

**Objective:** Add backend workflow.

**Files:** `.github/workflows/backend.yml`

**Steps:**

1. Add or update the focused test/contract that demonstrates add backend workflow.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `.github/workflows/backend.yml`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-083, CR-086, CR-096

**Parallel:** No

**Definition of Done:** Fmt, vet, staticcheck, race, migrations and coverage pass.

### CR-109

**Objective:** Add iOS workflow.

**Files:** `.github/workflows/ios.yml`

**Steps:**

1. Add or update the focused test/contract that demonstrates add ios workflow.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `.github/workflows/ios.yml`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-099, CR-100, CR-101, CR-102, CR-104

**Parallel:** No

**Definition of Done:** Pinned Simulator runs lint/tests and unsigned build.

### CR-110

**Objective:** Configure local SonarQube.

**Files:** `sonar-project.properties`

**Steps:**

1. Add or update the focused test/contract that demonstrates configure local sonarqube.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `sonar-project.properties`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-103, CR-106

**Parallel:** No

**Definition of Done:** Go and converted Swift coverage map correctly.

### CR-111

**Objective:** Add SonarQube workflow.

**Files:** `.github/workflows/quality.yml`

**Steps:**

1. Add or update the focused test/contract that demonstrates add sonarqube workflow.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `.github/workflows/quality.yml`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-108

**Parallel:** No

**Definition of Done:** Scan runs with reachable credentials; otherwise explicit skip.

### CR-112

**Objective:** Add final verification targets.

**Files:** `Makefile`

**Steps:**

1. Add or update the focused test/contract that demonstrates add final verification targets.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `Makefile`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-105, CR-106, CR-107, CR-109

**Parallel:** No

**Definition of Done:** Fast verify and slow E2E targets pass.

### CR-113

**Objective:** Write readiness runbook.

**Files:** `docs/development/release-readiness.md`

**Steps:**

1. Add or update the focused test/contract that demonstrates write readiness runbook.
2. Run the narrowest relevant command and confirm the new assertion fails for the expected reason.
3. Implement only the behavior described by this CR in `docs/development/release-readiness.md`.
4. Run the focused test, adjacent package tests, formatter/linter, and inspect the diff for secret or boundary leakage.

**Duration:** 15m

**Dependencies:** CR-110

**Parallel:** No

**Definition of Done:** Every acceptance criterion maps to reproducible evidence.

## Summary

- **Total number of tasks:** 113
- **Estimated total implementation time:** 1505 minutes (25.1 engineer-hours), excluding review and CI wait time.
- **Critical path:** Foundation API/TLS (CR-001 → CR-006 → CR-007 → CR-008 → CR-009 → CR-010 → CR-011 → CR-013 → CR-016 → CR-017), iOS composition (CR-019 → CR-021 → CR-022 → CR-024 → CR-025 → CR-034 → CR-035), then feature chains Auth → Catalog → Detail → Checkout → CI (CR-037 → CR-054 → CR-055 → CR-068 → CR-069 → CR-078 → CR-079 → CR-095 → CR-096 → CR-111 → CR-112 → CR-113).
- **Parallelizable tasks:** CR-001, CR-002. Particularly useful parallel groups are backend/iOS work within phases 3–6 and UI-test/security-workflow tasks in phase 7.

## Duration Verification

All 113 tasks use 5m, 10m, or 15m estimates. Automated validation confirms no duration exceeds 15 minutes, IDs are sequential, and every dependency points to an earlier CR. Two-file responsibilities were split except where the approved spec treats the same file as an existing composition or Make entry point.
