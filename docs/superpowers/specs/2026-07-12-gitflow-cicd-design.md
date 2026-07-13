# GitFlow CI/CD Design

## Purpose

Establish a strict GitFlow delivery process for the Commerce iOS and Go platform. Pull requests must pass deterministic policy, build, test, security, SonarQube, and Sourcery AI gates before protected branches can be updated.

This work is promoted ahead of the original Phase 7 quality backlog because the current pull request has no automated checks or review automation.

## Branch Model

- `main` contains production-ready history. It accepts pull requests only from `release/*` and `hotfix/*` branches.
- `develop` is the integration branch. It accepts pull requests from `feature/*`, `bugfix/*`, `release/*`, and `hotfix/*` branches.
- `feature/*` branches start from `develop` and contain product work.
- `bugfix/*` branches start from `develop` and contain non-production fixes.
- `release/*` branches start from `develop`, stabilize a release, and merge into both `main` and `develop`.
- `hotfix/*` branches start from `main` and merge into both `main` and `develop`.

Direct pushes, deletion, and force-pushes are blocked on `main` and `develop`. Protected branches require linear history, an up-to-date pull request, at least one human approval, resolved conversations, and all required status checks.

## Pipeline Architecture

The pipeline is split into independent workflows with stable check names and an aggregate quality gate.

### Pull Request Policy

`pr-policy.yml` runs on GitHub-hosted Ubuntu and:

- validates source and target branch combinations against GitFlow;
- rejects merge-ready pull requests that remain drafts;
- validates workflow YAML and shell scripts;
- enforces a conventional pull-request title and commit policy;
- uses concurrency cancellation for superseded commits on the same pull request.

### Backend

`backend.yml` runs on GitHub-hosted Ubuntu and:

- uses the Go version pinned in `.mise.toml`;
- runs formatting verification, `go vet`, `staticcheck`, race tests, and coverage;
- starts PostgreSQL, Redis, and Kafka only when integration tests require them;
- caches Go modules and build output using content-derived keys;
- uploads bounded diagnostic artifacts when a job fails.

### iOS

`ios.yml` runs on the GitHub-hosted Apple Silicon `macos-26` image and explicitly selects Xcode 26.6. It:

- verifies the pinned Xcode, Tuist, and SwiftLint toolchain;
- generates the Tuist workspace;
- runs SwiftLint, Core tests, DesignSystem tests, app unit tests, and UI tests;
- performs an unsigned generic iOS Simulator build without exporting an IPA;
- pins the simulator selection and reports available simulators when preflight fails;
- uploads `.xcresult` bundles and concise logs on failure.

Superseded iOS runs are cancelled through pull-request concurrency.

### Security

`security.yml` runs on GitHub-hosted Ubuntu and includes:

- CodeQL analysis for supported project languages;
- dependency review on pull requests;
- Gitleaks secret detection;
- Trivy filesystem and container scanning;
- CycloneDX SBOM generation and artifact upload.

Every third-party action is pinned to a full commit SHA. Workflow permissions default to `contents: read` and are elevated only for the job that requires them.

### SonarQube

`quality.yml` runs on GitHub-hosted `macos-26` and analyzes the repository with SonarQube for OSS. The OSS plan is required because the Free plan analyzes pull requests only when they target `main`, which cannot enforce `feature/* -> develop`. SonarQube for OSS only analyzes public repositories, matching this repository's visibility. Automatic Analysis stays off so the CI-based scanner is authoritative. The workflow:

- requires only `SONAR_TOKEN` as an Actions secret;
- identifies the combined repository project with `sonar.organization=jerry-nows` and `sonar.projectKey=jerry-nows_learning-superpower`;
- fails immediately with actionable guidance when a trusted run lacks the token;
- imports Go coverage and converted Swift coverage;
- waits for the SonarQube Quality Gate result and fails when the gate fails.

The combined project is an intentional exception to SonarSource's project-per-component monorepo recommendation because Swift and Go ship behind one repository gate and their reports are generated in one workspace. The stable repository aggregate remains authoritative because native monorepo PR blocking has limitations. Fork pull requests receive no secret, fail explicitly, and remain blocked; no `pull_request_target` workflow executes untrusted code.

### Aggregate Gate

The pull-request orchestration uses reusable workflow calls so a stable `Quality Gate` job can depend on Policy, Backend, iOS, Security, and SonarQube results. Branch protection requires both the individual checks and the aggregate check for transparent diagnosis.

Workflows also run after pushes to `develop` and `main`, and support manual `workflow_dispatch` execution.

## Sourcery AI Review

Sourcery is installed as a GitHub App for the repository. The Sourcery Dashboard is the source of truth for active AI review rules. `docs/development/sourcery-review-rules.md` is the auditable, copy-ready repository record of the Dashboard rules for:

- UIKit, MVVM-C, and Clean Architecture boundaries;
- Swift 6 concurrency and actor isolation;
- dependency injection and coordinator ownership;
- idiomatic Go and service boundaries;
- OWASP-aligned security and secret handling;
- test quality and regressions.

The repository-level `.sourcery.yaml` remains a minimal valid legacy configuration file and does not carry AI review instructions. Dashboard changes are saved, reloaded, and checked against the repository record; the repository validator checks the record's exact paths and blocking-state split.

Sourcery reviews new pull requests automatically. Existing PR #3 is triggered with the `@sourcery-ai review` command after configuration is pushed. The actual Sourcery check name is observed from that run before it is added to branch protection. Sourcery does not replace the required human approval.

## Repository Rules

GitHub rulesets protect `main` and `develop` with:

- pull requests required;
- one human approval required;
- stale approvals dismissed after material changes;
- conversations resolved;
- branch required to be current with its base;
- linear history required;
- force-push and deletion blocked;
- required checks for PR Policy, Backend, iOS, Security, SonarQube, and Quality Gate;
- the observed Sourcery check added after its first successful run;
- no administrator bypass by default.

The `develop` branch is created from the current `main` before the ruleset is enabled.

## Secrets and Runner Security

No credential, certificate, registration token, or runner secret is committed.

Public pull-request code runs only on fresh GitHub-hosted virtual machines. A personal self-hosted runner is never registered. The Sonar token is passed only to the trusted eligibility/scan job, is never printed, and is unavailable to fork pull requests.

## Local Validation and Operations

The repository provides:

- `make ci-validate` for actionlint, yamllint, shell syntax, and workflow contracts;
- `make ci-backend` for backend quality checks;
- `make ci-ios` for the pinned local iOS sequence;
- `make ci-security` for local security checks where supported;
- preflight scripts for tool versions, Simulator availability, optional local Docker/SonarQube reachability, and required environment values;
- a runbook for hosted CI, secrets, branch rules, failure recovery, and Sourcery verification.

Contract tests validate branch-policy decisions and required configuration without creating deliberately broken commits.

## Failure Behaviour

- A missing SonarQube token fails immediately and blocks a trusted pull request.
- A fork pull request cannot access the token and fails explicitly until evaluated from a trusted same-repository branch.
- A missing Simulator fails preflight and prints available destinations.
- A missing Sourcery review triggers an installation/access check followed by `@sourcery-ai review`.
- A failed security scanner blocks the pull request and preserves a sanitized report.
- Superseded pull-request runs are cancelled to conserve runner capacity.

## Delivery Sequence

1. Add CI/CD CR files promoted ahead of the original Phase 7 work.
2. Add policy contracts, workflow validators, runner preflight scripts, and Makefile commands.
3. Add the policy, backend, iOS, security, SonarQube, and aggregate workflows.
4. Add minimal legacy `.sourcery.yaml`, the auditable Dashboard review-rules record, and the CI/CD operations runbook.
5. Validate locally, commit, and push the workflow changes.
6. Create `develop` from `main`.
7. Configure the SonarQube Cloud project and repository secret; never register a personal runner.
8. Observe successful workflow check names and configure branch rulesets.
9. Trigger Sourcery on PR #3, observe its check name, and add it to both rulesets.

## Acceptance Criteria

- Pull requests that violate GitFlow are rejected.
- Pull requests to `develop` and `main` cannot merge without every strict quality gate.
- Backend and security jobs run on GitHub-hosted Ubuntu.
- iOS and SonarQube jobs run on GitHub-hosted `macos-26` with Xcode 26.6 selected.
- iOS lint, tests, UI smoke test, and unsigned build complete successfully.
- SonarQube fails closed when unavailable or misconfigured.
- Sourcery reviews PR #3 and its observed check is required by branch protection.
- Repository rules prevent direct pushes, deletion, and force-pushes to protected branches.
- Local validation and recovery procedures are reproducible from the runbook.
