# Sourcery Dashboard Review Rules

The Sourcery Dashboard is the source of truth for active AI review rules. This document is the repository's auditable, copy-ready record of the rules that were applied in the Dashboard and reload-verified. `.sourcery.yaml` is only a minimal legacy configuration file; it does not carry AI review instructions.

## Rule 1 — Swift 6 and MainActor correctness

- Paths: `Apps/**/*.swift,Packages/**/*.swift`
- Blocking: Yes
- Instructions: Review Swift changes for Swift 6 correctness and data races. Verify MainActor and other actor isolation, Sendable boundaries, and unstructured Task lifetime. Report only actionable findings, cite the affected file and line, explain the impact and evidence, and provide a concrete fix.

## Rule 2 — Clean Architecture, MVVM-C, Factory, and XCoordinator

- Paths: `Apps/**/*.swift,Packages/**/*.swift`
- Blocking: No
- Instructions: Review architecture boundaries. Domain code must remain framework-independent, MVVM-C responsibilities must remain separated, Factory registrations must preserve dependency direction, and XCoordinator must own navigation rather than view models. Report actionable findings with file-and-line evidence and a concrete fix.

## Rule 3 — Go, JWT, and OWASP

- Paths: `Backend/**/*.go`
- Blocking: Yes
- Instructions: Review Go changes for correctness, context propagation, error handling, concurrency safety, resource lifetime, and clear service boundaries. Review JWT authentication and authorization, and apply OWASP guidance to input validation, injection, sensitive-data exposure, and secret handling. Report actionable findings with the affected file and line, impact, evidence, and a concrete remediation.

## Rule 4 — Cross-repository correctness, security, and evidence

- Paths: `**/*`
- Blocking: Yes
- Instructions: Prioritize correctness and security defects. Report only issues supported by changed-code evidence; cite the affected file and line, explain the concrete impact and remediation, and do not speculate, duplicate findings, or report formatting noise already enforced by SwiftLint or gofmt.

## Rule 5 — Regression tests, mocks, and UI recovery

- Paths: `**/*Tests.swift,**/*_test.go,Apps/**/UITests/**/*.swift`
- Blocking: No
- Instructions: Require a regression test for every behavior fix and meaningful tests for new behavior, including failure paths and concurrency-sensitive behavior. Review mocks for behavior fidelity and isolation. Review UI tests for deterministic state setup, recovery, and actionable failure evidence.

## Dashboard setup

1. Open the repository in Sourcery Dashboard and select Review Rules.
2. Create or update each rule with the exact name, comma-separated Paths value, Blocking state, and Instructions above.
3. Save all five rules.
4. Reload the Dashboard, reopen each rule, and compare its paths, blocking state, and instructions with this document.

## Verification

Run the repository contract after every Dashboard-rule copy update:

```bash
bash Infrastructure/ci/tests/sourcery_config_test.sh
```

The contract verifies the five-rule audit artifact, the three-blocking/two-nonblocking split, the minimal legacy YAML shape, and guards against source exclusions and embedded secrets. Dashboard reload verification remains the operational proof that the rules are active.
