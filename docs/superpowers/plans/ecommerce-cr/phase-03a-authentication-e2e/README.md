# Phase 3A — Authentication End-to-End Completion

This amendment closes the dependencies missing from CR-037 through CR-054. IDs continue from the original 128-task plan; dependency order, rather than numeric order, governs execution.

## Execution order

1. Package and dependency prerequisites: CR-129, CR-132, CR-134.
2. Backend persistence foundation: CR-037, CR-135, CR-136, CR-038.
3. Backend auth primitives: CR-039 through CR-043.
4. Backend repositories and tests: CR-137 through CR-140.
5. Backend service and transport: CR-044 through CR-046, then CR-141 through CR-145.
6. iOS shared security/networking: CR-049 through CR-051, then CR-130, CR-131, CR-133.
7. Login feature and data layer: CR-047, CR-048, CR-146 through CR-149, then CR-052 through CR-054 and CR-158 through CR-160.
8. App integration: CR-150 through CR-152.
9. Local-stack integration: CR-161, CR-153 through CR-157.

## CR files

- [CR-129](CR-129.md) — Security package manifest
- [CR-130](CR-130.md) — Keychain token-store tests
- [CR-131](CR-131.md) — Biometric-gate tests
- [CR-132](CR-132.md) — Networking package manifest
- [CR-133](CR-133.md) — Refresh single-flight tests
- [CR-134](CR-134.md) — Backend auth dependencies
- [CR-135](CR-135.md) — Migration runner
- [CR-136](CR-136.md) — Migration integration test
- [CR-137](CR-137.md) — PostgreSQL user repository
- [CR-138](CR-138.md) — PostgreSQL user-repository test
- [CR-139](CR-139.md) — Redis refresh-session repository
- [CR-140](CR-140.md) — Redis refresh-session test
- [CR-141](CR-141.md) — Seeded demo user command
- [CR-142](CR-142.md) — Auth HTTP composition
- [CR-143](CR-143.md) — API dependency wiring
- [CR-144](CR-144.md) — OpenAPI auth contract
- [CR-145](CR-145.md) — Backend auth lifecycle integration test
- [CR-146](CR-146.md) — Moya auth target
- [CR-147](CR-147.md) — Auth remote data source
- [CR-148](CR-148.md) — Login repository
- [CR-149](CR-149.md) — Login data integration test
- [CR-150](CR-150.md) — Commerce app package dependencies
- [CR-151](CR-151.md) — App auth composition
- [CR-152](CR-152.md) — Root login flow integration
- [CR-153](CR-153.md) — Compose auth environment
- [CR-154](CR-154.md) — Local auth environment template
- [CR-155](CR-155.md) — Auth developer commands
- [CR-156](CR-156.md) — Local auth smoke flow
- [CR-157](CR-157.md) — Login XCUITest journey
- [CR-158](CR-158.md) — Login view-model tests
- [CR-159](CR-159.md) — Login controller tests
- [CR-160](CR-160.md) — Login coordinator tests
- [CR-161](CR-161.md) — Backend runtime image

## Added estimate

- Tasks: 33
- Engineering time: 450 minutes
- Revised plan total: 161 tasks, 2,180 minutes (36.3 engineer-hours), excluding review and CI wait time.
