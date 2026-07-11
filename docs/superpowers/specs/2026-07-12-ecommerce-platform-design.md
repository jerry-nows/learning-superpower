# Ecommerce Platform Design

Date: 2026-07-12
Status: approved for implementation planning

## 1. Objective

Build a production-oriented ecommerce system that runs end-to-end on a local development environment:

- an iOS 17+ application built with UIKit, Clean Architecture, MVVM-C, Swift 6 strict concurrency, Tuist, and local Swift Package Manager modules;
- a Go modular-monolith API;
- PostgreSQL, Redis, Kafka in KRaft mode, and a TLS reverse proxy managed by Docker Compose;
- automated linting, tests, security checks, SonarQube integration, and unsigned iOS builds in GitHub Actions.

The customer journey is login, browse/search/filter products, view progressively loaded product details, add items to a persistent cart, place a COD order, see a success notification, and return to the catalog root.

The first release does not include registration, password recovery, card payments, a web administration interface, cloud deployment, IPA export, or App Store deployment.

## 2. Product Requirements

### 2.1 Authentication

- Users sign in with an email and password using an account seeded by the backend.
- Users can sign out.
- An authenticated session can be reopened with Face ID. Cancellation or biometric failure falls back to email/password login.
- Access tokens are JWTs with a 60-second lifetime.
- Refresh tokens are opaque, rotated on every use, and protected by reuse detection.
- The iOS app stores credentials only in Keychain with a `ThisDeviceOnly` accessibility policy. Tokens never enter UserDefaults, Core Data, logs, analytics, or backups.

### 2.2 Catalog

- The catalog supports cursor-based pagination, pull-to-refresh, and debounced search.
- Users can browse categories and apply filters and sorting.
- Pagination preserves the active search, category, filters, and sort order.
- Seed data represents a multi-category lifestyle catalog: fashion, accessories, home goods, and personal care.
- The interface supports Vietnamese and English; prices use VND.

### 2.3 Product Detail

Product information, inventory, rating summary, and comments are independent sections backed by separate API requests. They start concurrently and render progressively:

- a completed section replaces only its own skeleton;
- a pending section keeps its skeleton;
- a failed section presents an inline retry state without hiding successful sections;
- reconnect recovery retries only failed or unfinished sections that still belong to a live screen.

### 2.4 Cart and COD Checkout

- The cart is persisted locally per authenticated user.
- Quantity changes and removal are local operations.
- The server revalidates price, product availability, and stock before order creation.
- Checkout collects recipient name, phone number, delivery address, and an optional note.
- COD order creation uses an idempotency key but is never automatically retried after network loss or timeout.
- When submission becomes ambiguous, the app queries order status by idempotency key and presents a specific outcome or a user-initiated retry option.
- Successful checkout clears the committed cart, shows a localized success notification, and returns to the catalog root.

### 2.5 Connectivity and Accessibility

- A small global banner, visually similar to YouTube's connectivity notification, reports offline and restored states.
- Cached useful content remains visible while unfinished content uses skeletons.
- Safe reads are registered for deduplicated, lifecycle-aware recovery and resume with bounded exponential backoff and jitter.
- Validation, authorization, TLS-pinning, login, and order-creation failures do not auto-retry.
- The app supports Light and Dark Mode, Dynamic Type, VoiceOver, Reduce Motion, minimum 44-point targets, and WCAG 2.2 AA contrast.
- The app runs on iOS Simulator and a physical iPhone on the same LAN as the local stack.

## 3. Architecture

### 3.1 Repository Shape

The repository is a monorepo with four top-level concerns:

```text
Apps/CommerceApp/              Tuist iOS application and composition root
Packages/                      Local iOS SPM packages
Backend/                       Go modular monolith
Infrastructure/               Docker Compose, TLS, Kafka, SonarQube, scripts
```

Tuist generates a reproducible Xcode workspace. Swift package manifests define module boundaries; the generated Xcode project is not the architectural source of truth.

### 3.2 iOS Feature Packages

The application uses vertical feature modules:

- `LoginFeature`
- `CatalogFeature`
- `CartCheckoutFeature`

Each feature owns Presentation, Domain, and Data implementations. Presentation uses UIKit, MVVM-C, and XCoordinator. Domain code contains entities, use cases, repository protocols, and typed errors; it does not import UIKit, Moya, Factory, Core Data, Realm, or XCoordinator. Data code maps transport and persistence models into domain models.

Features never import one another. Each exposes only immutable `Sendable` flow input/config values, a flow factory, and a typed result/action enum. Representative contracts are:

- `LoginFlowInput` and `LoginResult.authenticated(userID)`;
- `CatalogFlowInput`, `CatalogAction.openProduct`, `openCart`, and `logout`;
- `CartFlowInput` and `CheckoutResult.completed(orderID)` or `cancelled`.

The application-level coordinator translates one feature's action into another feature's input. Feature ViewModels, repositories, DTOs, persistence types, and view controllers are not public contracts.

### 3.3 Shared iOS Packages

- `Core`: common value types and cross-cutting error primitives; it contains no feature business rules.
- `Networking`: Moya providers and targets, decoding, auth retry, request metadata, and TLS verification.
- `Persistence`: Core Data stack, migrations, and repository adapters.
- `Security`: Keychain, LocalAuthentication, token storage, and pin configuration.
- `DesignSystem`: semantic tokens and reusable UIKit components.
- `Connectivity`: `NWPathMonitor`, pending request registry, retry policy, and global connection state.
- `Observability`: structured logging, trace identifiers, metrics hooks, and mandatory redaction.
- `TestSupport`: fixtures, deterministic clocks/UUIDs, builders, stubs, and spies without business assertions.

Factory registrations live at the application composition root or a narrowly scoped package factory boundary. Domain objects receive dependencies through initializers and never call Factory directly.

### 3.4 Persistence Decision

Core Data is the only object database in the first release. It stores catalog records, categories, normalized-query result ordering, cache metadata, and per-user carts. It uses background contexts, explicit migrations, and repository abstractions.

Realm is deliberately excluded until a module demonstrates a measured need for Realm-specific live queries or object-graph behavior. Repository protocols keep a future adapter possible without exposing persistence types. Product images use a quota-controlled URL/disk image cache. Security credentials remain exclusively in Keychain.

## 4. iOS Data and State Flow

### 4.1 Catalog Queries

A normalized query key comprises language, search text, category, filters, sort, and page-size inputs. The UI can render cached results immediately, then reconcile them with the server. Pull-to-refresh replaces the first-page snapshot atomically. Search uses a 350 ms debounce and cancels obsolete tasks. Load-more requests are deduplicated per query and cursor.

### 4.2 Product Detail Concurrency

The Product Detail ViewModel owns one explicit state value per section. A structured task group starts product, inventory, rating-summary, and comments requests concurrently. Child results update only their section on `MainActor`. Leaving the screen cancels its task tree and unregisters pending recovery work.

UIKit uses compositional layout and diffable data sources to update sections independently. Skeleton geometry matches final content geometry to prevent layout jumps.

### 4.3 Connectivity Recovery

`NWPathMonitor` provides a connectivity signal, not proof that the API is reachable. A concurrency-safe registry records only retryable failures with a deduplication key, weak/lifecycle owner, attempt count, and retry policy. When connectivity appears restored, requests resume with jitter and bounded attempts. Completed, cancelled, stale-owner, and non-retryable entries are removed.

### 4.4 Checkout Consistency

The client requests a current quote before order submission. `POST /orders` carries an idempotency key. The server transaction validates the quote, locks and checks inventory, persists immutable item-price snapshots, creates the order, reserves stock, and writes an outbox event in one PostgreSQL commit. Kafka is outside the synchronous response path.

## 5. Backend and Infrastructure

### 5.1 Go Modular Monolith

The Go API has bounded modules for Auth, Catalog, Reviews, Inventory, Orders, and platform concerns. Modules communicate through explicit service interfaces and domain events rather than shared database access helpers. HTTP handlers validate and map input; business services own rules; repositories own persistence.

PostgreSQL is the source of truth for users, products, categories, inventory, reviews/comments, orders, order items, and outbox events. Redis stores refresh-token sessions and revocation state, rate-limit counters, and disposable caches; it never holds the only copy of business data.

### 5.2 Kafka

Kafka runs in KRaft mode locally. A transactional-outbox relay publishes order and inventory events after the database commit. Consumers are idempotent by event ID. Bounded retry topics precede dead-letter topics. Kafka outages do not change a successfully committed COD response; the outbox delivers later.

### 5.3 Local TLS

Caddy terminates HTTPS and forwards to the Go API. `mkcert` creates a development CA and certificates for configured LAN hostnames/IPs. Developers install the CA on Simulator and physical devices. The app pins SHA-256 SPKI hashes with primary and backup pins per environment and fails closed.

Private keys, generated certificates, tokens, and machine-specific addresses are ignored by Git and supplied through local environment files or CI secrets.

### 5.4 HTTP API v1

The initial surface is:

```text
POST /v1/auth/login
POST /v1/auth/refresh
POST /v1/auth/logout
GET  /v1/products
GET  /v1/products/{id}
GET  /v1/products/{id}/inventory
GET  /v1/products/{id}/rating-summary
GET  /v1/products/{id}/comments
GET  /v1/categories
POST /v1/orders/quote
POST /v1/orders
GET  /v1/orders/by-idempotency-key/{key}
```

OpenAPI is the source contract for validation and fixtures. Moya targets remain explicit within feature data packages, and generated transport types never enter Domain.

## 6. Security and Error Model

The design follows OWASP MASVS/MSTG and OWASP API Security principles:

- passwords are hashed with calibrated Argon2id parameters and never logged;
- refresh-token hashes and token-family state are held in Redis;
- reuse detection revokes the entire refresh family;
- an `AuthRefreshActor` implements single-flight refresh when concurrent requests receive 401;
- awaiting requests retry at most once after successful refresh;
- failed refresh clears secrets and returns to Login;
- ATS remains strict, arbitrary loads are disabled, and pin mismatch is non-retryable;
- request bodies, response bodies, tokens, credentials, addresses, and phone numbers are redacted from logs;
- the API applies schema validation, body and timeout limits, authorization, rate limiting, deny-by-default CORS, security headers, and least-privilege database credentials;
- secrets and private keys never enter source control.

The API returns stable error codes, a trace ID, optional field violations, and retryability metadata. It never returns stack traces. Code families include `AUTH_*`, `CATALOG_*`, `CART_*`, and `ORDER_*`. The app maps codes to localized Vietnamese/English copy.

## 7. User Interface Design

The approved direction is Editorial Minimal:

- a warm-neutral semantic palette with independently designed Light and Dark themes;
- serif display typography for editorial headings and system sans-serif for controls and body copy;
- an 8-point spacing grid, consistent image ratios, restrained motion, and generous whitespace;
- reusable UIKit components including `ProductCard`, `PriceView`, `StockBadge`, `RatingSummary`, `SkeletonSection`, `ConnectivityBanner`, and empty/error states.

The screen journey is Login, Catalog, Product Detail, Cart, COD Checkout, and Success. The success state returns to the existing catalog root instead of creating a second catalog stack.

Feature configurations control biometric policy, localized copy, page size, enabled filters/sorts, initial category, cache policy, quantity limits, COD availability, and checkout validation rules.

## 8. Testing Strategy

### 8.1 iOS

- Swift Testing is the default unit-test framework.
- Swift Mocking generates Swift 6 concurrency-safe protocol mocks.
- Mocker intercepts `URLSession` traffic for deterministic Moya integration tests.
- in-memory Core Data stores test repositories, migrations, query ordering, and per-user cart isolation.
- XCUITest covers critical user journeys.
- SnapshotTesting covers UIKit visual regression in Light/Dark, Vietnamese/English, and representative Dynamic Type sizes.
- Snapshot tests run on one pinned simulator model and runtime in CI.

### 8.2 Backend

- Go's `testing` package and Testify cover domain/service tests.
- `go test -race` is mandatory.
- testcontainers-go runs real PostgreSQL, Redis, and Kafka for repository, migration, outbox, retry, DLT, and idempotency tests.
- API tests validate OpenAPI responses, token rotation/reuse, authorization, stock conflicts, and idempotent checkout.

### 8.3 End-to-End

Docker Compose starts TLS, the API, seeded dependencies, and infrastructure. A small XCUITest suite verifies login, catalog-to-detail progressive loading, offline recovery, persistent cart, COD success, and explicit COD failure handling.

Coverage gates are package-specific: Domain and use-case packages require higher coverage than UI wiring. Coverage percentage is not used as a substitute for behavioral assertions.

## 9. CI/CD

GitHub Actions runs pull-request jobs in parallel where dependencies allow:

1. validate Tuist manifests, SPM resolution, OpenAPI, migrations, and Docker Compose configuration;
2. run SwiftLint in strict mode, `gofmt`, `go vet`, Staticcheck, secret scanning, dependency review, and container/dependency vulnerability scans;
3. run iOS unit/snapshot tests and Go unit/race tests;
4. run backend integration tests with containers;
5. run the local-stack E2E smoke suite;
6. run `xcodebuild build-for-testing` with signing disabled;
7. upload logs, test reports, coverage, diffs, and SBOM artifacts.

The repository includes a local Docker Compose SonarQube profile and scanner commands. GitHub Actions runs SonarQube analysis only when `SONAR_HOST_URL` and `SONAR_TOKEN` target a reachable service. Until those are configured, the job is explicitly reported as skipped and is not represented as a passed quality gate. Go coverage and converted Swift generic coverage feed the scanner.

No Apple Developer account is required. CI builds the Simulator application without code signing and does not archive or export an IPA.

## 10. Developer Workflow

The intended entry points are:

```text
make bootstrap   verify Tuist, Xcode, Go, Docker, mkcert, and required tools
make certs       generate local certificates and print trust instructions
make infra-up    start PostgreSQL, Redis, Kafka, Caddy, and the Go API
make seed        apply deterministic demo users and lifestyle catalog data
make generate    generate/open the Tuist workspace
make verify      run fast lint, unit, and integration checks
make e2e         run the complete local end-to-end smoke suite
```

Host addressing and pin sets are environment configuration. Simulator uses a local host mapping; physical devices use a configured LAN hostname/IP covered by the certificate.

## 11. Delivery Decomposition

Implementation planning should split the approved system into sequential milestones while keeping an executable vertical slice:

1. repository/toolchain foundation and local infrastructure;
2. shared iOS platform packages and design system;
3. authentication end-to-end;
4. catalog list/search/filter/cache end-to-end;
5. progressive product detail and connectivity recovery;
6. persistent cart and COD checkout with outbox/Kafka;
7. full security hardening, accessibility, localization, E2E, SonarQube, and CI quality gates.

Each milestone must leave main buildable and must include its own tests. No milestone may bypass feature contracts by introducing direct feature-to-feature imports.

## 12. Acceptance Criteria

- A developer can bootstrap the stack from a clean supported macOS machine using documented commands.
- The app builds for an iOS 17+ Simulator without signing and can connect through pinned local HTTPS.
- A physical iPhone on the LAN can trust the local CA and run the same flow with environment-specific host configuration.
- The seeded user can log in, refresh a 60-second access token without duplicate concurrent refreshes, use Face ID to reopen a session, and log out.
- Catalog pagination, refresh, search, category, filter, sort, caching, and bilingual UI behave consistently.
- Product-detail sections render independently and resume only unfinished safe requests after reconnection.
- The offline banner appears and clears without blocking cached content.
- Cart contents survive app restart and remain isolated by user.
- COD checkout detects price/stock changes, is idempotent, never auto-retries creation, and returns to the catalog after confirmed success.
- PostgreSQL remains the business source of truth; Kafka events originate from the committed outbox and consumers tolerate duplicates.
- CI enforces lint, tests, race checks, contract checks, security scans, and unsigned build success.
- No token, password, certificate private key, address, phone number, or other sensitive value appears in committed files or diagnostic logs.
