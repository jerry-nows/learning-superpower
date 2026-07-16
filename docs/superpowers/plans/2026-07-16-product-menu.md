# Product Menu Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Product/Menu flow with paginated product browsing, pull-to-refresh, search, categories, filtering, sorting, product details, reviews, comments, stock sections, offline resume, and skeleton loading.

**Architecture:** The backend exposes read-only product endpoints backed by PostgreSQL. The iOS `MenuFeature` SPM package owns domain contracts, Moya transport, repository/cache, UIKit presentation, and XCoordinator flow boundaries. Product detail sections load independently through task groups so completed sections render while unresolved sections remain skeletons.

**Tech Stack:** Go, PostgreSQL, Chi, Moya, UIKit, Swift Concurrency, Factory, XCoordinator, CoreData, Swift Testing/XCTest.

## Global Constraints

- Access tokens are supplied through the existing authenticated API boundary.
- Product list requests support page, page size, query, category, sort field, and sort direction.
- Detail sections are independently cancellable and independently cacheable.
- Offline state must show a non-blocking banner and resume failed read requests after connectivity returns.
- Payment is not part of this phase; no cart or checkout behavior is added here.
- Every CR remains independently testable and no larger than 15 minutes.

---

### Task 162 (CR-162): Product backend package boundary

**Files:** Create `Backend/internal/product/model.go`, `Backend/internal/product/model_test.go`.

- [ ] Define `Product`, `ProductPage`, `ProductQuery`, and `ProductSort` with JSON-safe fields.
- [ ] Add tests for defaults, invalid page sizes, and stable sort values.
- [ ] Run `cd Backend && go test ./internal/product`.
- [ ] Commit `feat(product): define backend product contracts`.

### Task 163 (CR-163): Product database migration

**Files:** Create `Backend/migrations/000002_product.sql`, `Backend/migrations/product_migration_contract_test.go`.

- [ ] Create products and categories tables with UUID, price, stock, status, timestamps, and indexes.
- [ ] Add reversible migration assertions and foreign-key constraints.
- [ ] Run migration contract tests.
- [ ] Commit `feat(product): add product schema`.

### Task 164 (CR-164): Product repository contract

**Files:** Create `Backend/internal/product/repository.go`, `Backend/internal/product/repository_test.go`.

- [ ] Define `ProductRepository` methods for page queries, product lookup, category listing, reviews, comments, and stock.
- [ ] Add deterministic fake repository tests for empty and populated responses.
- [ ] Commit `feat(product): define repository boundary`.

### Task 165 (CR-165): PostgreSQL product repository

**Files:** Create `Backend/internal/product/postgres_repository.go`, `Backend/internal/product/postgres_repository_test.go`.

- [ ] Implement parameterized queries for pagination, search, category, filter, and sort.
- [ ] Cap page size and validate sort columns through an allow-list.
- [ ] Add integration coverage using the existing PostgreSQL test container pattern.
- [ ] Commit `feat(product): implement postgres product repository`.

### Task 166 (CR-166): Product HTTP handlers

**Files:** Create `Backend/internal/product/handler.go`, `Backend/internal/product/handler_test.go`.

- [ ] Implement `GET /v1/products`, `GET /v1/products/{id}`, and `GET /v1/categories`.
- [ ] Return consistent JSON errors and pagination metadata.
- [ ] Add handler tests for auth, invalid query, empty page, and success.
- [ ] Commit `feat(product): add product list handlers`.

### Task 167 (CR-167): Product detail section handlers

**Files:** Modify `Backend/internal/product/handler.go`; create `Backend/internal/product/detail_handler_test.go`.

- [ ] Implement reviews, comments, and stock endpoints as independent reads.
- [ ] Ensure one section failure does not affect another endpoint response.
- [ ] Add tests for successful and unavailable sections.
- [ ] Commit `feat(product): expose detail sections`.

### Task 168 (CR-168): Product router and API wiring

**Files:** Modify `Backend/internal/platform/httpapi/router.go`, `Backend/cmd/api/main.go`; create `Backend/internal/product/router_contract_test.go`.

- [ ] Register product routes behind the existing access-token middleware.
- [ ] Wire PostgreSQL product repository into the composition root.
- [ ] Verify route method and path contracts.
- [ ] Commit `feat(product): wire product api`.

### Task 169 (CR-169): Product seed data

**Files:** Modify `Backend/cmd/seed/main.go`; create `Backend/cmd/seed/product_seed_test.go`, `Infrastructure/tests/product_seed_test.sh`.

- [ ] Seed categories and deterministic products for local development.
- [ ] Keep seed idempotent and avoid logging credentials or secrets.
- [ ] Add shell contract test.
- [ ] Commit `test(product): add deterministic product seed`.

### Task 170 (CR-170): MenuFeature package manifest

**Files:** Create `Packages/MenuFeature/Package.swift`, `Packages/MenuFeature/Sources/MenuDomain/MenuDomain.swift`, `Packages/MenuFeature/Tests/MenuDomainTests/MenuDomainTests.swift`.

- [ ] Declare dependencies on Core, DesignSystem, Networking, and Security.
- [ ] Add a compile/import contract test.
- [ ] Commit `chore(menu): declare MenuFeature package`.

### Task 171 (CR-171): Menu domain contracts

**Files:** Create `Packages/MenuFeature/Sources/MenuDomain/ProductContracts.swift`, `Packages/MenuFeature/Tests/MenuDomainTests/ProductContractsTests.swift`.

- [ ] Define product, category, filter, sort, pagination, and detail section state models.
- [ ] Add tests for stable identity and skeleton-ready state transitions.
- [ ] Commit `feat(menu): define product domain contracts`.

### Task 172 (CR-172): Menu Moya targets

**Files:** Create `Packages/MenuFeature/Sources/MenuData/ProductTarget.swift`, `Packages/MenuFeature/Tests/MenuDataTests/ProductTargetTests.swift`.

- [ ] Encode list query parameters and detail endpoints using allow-listed values.
- [ ] Add redaction tests for access tokens and query payloads.
- [ ] Commit `feat(menu): add product api targets`.

### Task 173 (CR-173): Menu remote data source

**Files:** Create `Packages/MenuFeature/Sources/MenuData/ProductRemoteDataSource.swift`, `Packages/MenuFeature/Tests/MenuDataTests/ProductRemoteDataSourceTests.swift`.

- [ ] Implement async Moya requests with cancellation and per-request decoding.
- [ ] Map HTTP, transport, malformed-response, and cancellation errors.
- [ ] Add success, failure, malformed, and cancellation tests.
- [ ] Commit `feat(menu): implement product remote source`.

### Task 174 (CR-174): Product cache repository

**Files:** Create `Packages/MenuFeature/Sources/MenuData/ProductRepository.swift`, `Packages/MenuFeature/Sources/MenuData/ProductCacheStore.swift`, `Packages/MenuFeature/Tests/MenuDataTests/ProductRepositoryTests.swift`.

- [ ] Cache list and detail sections using CoreData-backed storage.
- [ ] Return stale cache with freshness metadata when offline.
- [ ] Add tests for cache hit, cache miss, invalidation, and stale fallback.
- [ ] Commit `feat(menu): add product cache repository`.

### Task 175 (CR-175): Connectivity resume coordinator

**Files:** Modify `Packages/Core/Sources/Core/ConnectivityMonitor.swift`; create `Packages/MenuFeature/Sources/MenuData/ProductResumeCoordinator.swift`, tests.

- [ ] Expose an async connectivity stream.
- [ ] Retry only failed read requests after connectivity returns.
- [ ] Never automatically retry payment or mutation requests.
- [ ] Commit `feat(menu): resume product reads after connectivity`.

### Task 176 (CR-176): Product list view model

**Files:** Create `Packages/MenuFeature/Sources/MenuPresentation/ProductListViewModel.swift`, tests.

- [ ] Implement initial load, pagination, pull-to-refresh, search debounce, category, filter, and sort state.
- [ ] Preserve loaded rows while showing next-page skeletons.
- [ ] Add deterministic async state tests.
- [ ] Commit `feat(menu): add product list view model`.

### Task 177 (CR-177): Product detail view model

**Files:** Create `Packages/MenuFeature/Sources/MenuPresentation/ProductDetailViewModel.swift`, tests.

- [ ] Launch product, reviews, comments, and stock requests concurrently.
- [ ] Update each section independently and preserve skeleton state for pending sections.
- [ ] Add partial-success, cancellation, offline, and all-success tests.
- [ ] Commit `feat(menu): add concurrent product detail loading`.

### Task 178 (CR-178): Product list UIKit screen

**Files:** Create `Packages/MenuFeature/Sources/MenuPresentation/ProductListViewController.swift`, tests.

- [ ] Build accessible table/collection UI with pull-to-refresh, search, category/filter/sort controls, and skeleton cells.
- [ ] Add UI tests for loading, refresh, pagination, and empty state.
- [ ] Commit `feat(menu): add product list screen`.

### Task 179 (CR-179): Product detail UIKit screen

**Files:** Create `Packages/MenuFeature/Sources/MenuPresentation/ProductDetailViewController.swift`, tests.

- [ ] Render product, reviews, comments, stock, and per-section skeleton/error states.
- [ ] Add accessibility identifiers and dynamic type support.
- [ ] Commit `feat(menu): add product detail screen`.

### Task CR-180: Menu coordinator and app route

**Files:** Create `Packages/MenuFeature/Sources/MenuPresentation/MenuCoordinator.swift`; modify `Apps/CommerceApp/Sources/Composition/AppContainer.swift`, `Apps/CommerceApp/Sources/Navigation/AppCoordinator.swift`; add tests.

- [ ] Expose only `MenuFlowInput` and `MenuResult` at the module boundary.
- [ ] Wire Factory composition and route authenticated login into ProductList.
- [ ] Add coordinator replacement and route transition tests.
- [ ] Commit `feat(menu): wire product flow into app`.

### Task CR-181: Product API integration and CI contracts

**Files:** Create `Backend/integration/product_lifecycle_test.go`, `Infrastructure/tests/product_e2e_test.sh`, modify `.github/workflows/backend.yml`, `.github/workflows/ios.yml`.

- [ ] Verify seeded list/search/detail requests against PostgreSQL and Redis-backed API startup.
- [ ] Add CI commands for backend integration and MenuFeature tests.
- [ ] Run Go race tests, SwiftLint, package tests, and simulator build.
- [ ] Commit `test(product): add end-to-end menu coverage`.

## Execution Order

- CR-162 through CR-169 are backend sequential tasks; CR-170 can start after CR-162 in parallel.
- CR-171 through CR-175 are iOS data tasks and depend on CR-170.
- CR-176 and CR-177 can run in parallel after CR-174.
- CR-178 and CR-179 can run in parallel after their view models.
- CR-180 depends on CR-178 and CR-179; CR-181 is final integration.

## Verification

- Every task has a focused test command and a single primary responsibility.
- No task requires more than 15 minutes for an experienced engineer.
- Backend, iOS data, presentation, and integration boundaries are separately reviewable.
