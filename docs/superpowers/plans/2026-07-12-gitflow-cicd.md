# Strict GitFlow CI/CD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add strict GitFlow enforcement, split GitHub Actions quality gates, local SonarQube integration, self-hosted iOS automation, Sourcery review standards, and protected `main`/`develop` branches.

**Architecture:** A top-level `ci.yml` calls reusable policy, backend, iOS, security, and SonarQube workflows, then exposes a stable aggregate `Quality Gate` job. Linux work runs on GitHub-hosted Ubuntu; Xcode and local SonarQube work run on the labelled Apple Silicon self-hosted runner. Shell scripts own testable policy and preflight logic, while workflows remain thin orchestration layers.

**Tech Stack:** GitHub Actions, Bash, actionlint, yamllint, Go 1.26.5, Tuist 4.202.1, SwiftLint 0.65.0, Xcode 26.6, Docker Compose, SonarQube, CodeQL, Gitleaks, Trivy, CycloneDX, Sourcery AI.

## Global Constraints

- GitFlow branches are `main`, `develop`, `feature/*`, `bugfix/*`, `release/*`, and `hotfix/*`.
- Direct pushes, deletion, and force-pushes are blocked on `main` and `develop`.
- Protected branches require linear history, current branches, one human approval, resolved conversations, and all required checks.
- Backend and security run on GitHub-hosted Ubuntu.
- iOS and SonarQube run on `self-hosted`, `macOS`, `ARM64`, `commerce-ios`.
- SonarQube fails closed when `SONAR_HOST_URL`, `SONAR_TOKEN`, or the server is unavailable.
- No IPA export or Apple Developer credential is required.
- Third-party actions are pinned to immutable full commit SHAs.
- No token, certificate, runner credential, or secret is committed or printed.
- Each CR is written as a separate file under `docs/superpowers/plans/ecommerce-cr/phase-02b-cicd-foundation/`.

---

### Task 1: Register promoted CI/CD CRs

**Files:**
- Create: `docs/superpowers/plans/ecommerce-cr/phase-02b-cicd-foundation/README.md`
- Create: `docs/superpowers/plans/ecommerce-cr/phase-02b-cicd-foundation/CR-114.md` through `CR-128.md`
- Modify: `docs/superpowers/plans/ecommerce-cr/README.md`

**Interfaces:**
- Consumes: approved GitFlow CI/CD spec.
- Produces: ordered CR-114–CR-128 task contracts that map one-to-one to Tasks 2–16 below.

- [ ] **Step 1: Add the phase index and CR contracts**

Use this exact CR mapping: `CR-114 branch policy`, `CR-115 policy tests`, `CR-116 runner preflight`, `CR-117 Sonar preflight`, `CR-118 CI validation`, `CR-119 PR policy workflow`, `CR-120 backend workflow`, `CR-121 iOS workflow`, `CR-122 security workflow`, `CR-123 SonarQube configuration`, `CR-124 quality workflow`, `CR-125 aggregate workflow`, `CR-126 Sourcery standards`, `CR-127 CI commands/runbook`, `CR-128 GitHub repository setup`. Each CR must include Objective, Files, Steps, Duration, Dependencies, Parallel, and Definition of Done.

- [ ] **Step 2: Validate IDs and placeholders**

Run:

```bash
rg -n "^# CR-1(1[4-9]|2[0-8])$" docs/superpowers/plans/ecommerce-cr/phase-02b-cicd-foundation
rg -n "TBD|TODO|FIXME" docs/superpowers/plans/ecommerce-cr/phase-02b-cicd-foundation && exit 1 || true
```

Expected: exactly 15 CR headings and no placeholder match.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/ecommerce-cr
git commit -m "docs: promote CI/CD foundation backlog"
```

### Task 2: Implement GitFlow branch policy

**Files:**
- Create: `Infrastructure/ci/validate-gitflow.sh`
- Test: `Infrastructure/ci/tests/validate-gitflow_test.sh`

**Interfaces:**
- Consumes: `BASE_REF`, `HEAD_REF`, `PR_DRAFT`, `PR_TITLE` environment variables.
- Produces: exit `0` for valid GitFlow PRs; exit `1` with an actionable message otherwise.

- [ ] **Step 1: Write the failing shell contract**

Cover these exact cases: `feature/cart -> develop` passes, `release/1.0.0 -> main` passes, `hotfix/cve -> main` passes, `feature/cart -> main` fails, `main -> develop` fails, draft PR fails, and a non-Conventional title fails.

```bash
run_policy() {
  BASE_REF="$1" HEAD_REF="$2" PR_DRAFT="$3" PR_TITLE="$4" \
    bash Infrastructure/ci/validate-gitflow.sh 2>&1
}
```

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/validate-gitflow_test.sh`

Expected: FAIL because `Infrastructure/ci/validate-gitflow.sh` does not exist.

- [ ] **Step 3: Implement the policy**

Use `case "$BASE_REF:$HEAD_REF"` to allow only the branch pairs in the spec, reject `PR_DRAFT=true`, and validate `PR_TITLE` against:

```bash
^(feat|fix|chore|docs|test|refactor|perf|build|ci|revert)(\([a-z0-9._-]+\))?!?: .+
```

- [ ] **Step 4: Verify GREEN and syntax**

Run:

```bash
bash Infrastructure/ci/tests/validate-gitflow_test.sh
bash -n Infrastructure/ci/validate-gitflow.sh
```

Expected: all seven cases pass and shell syntax is valid.

- [ ] **Step 5: Commit**

```bash
git add Infrastructure/ci/validate-gitflow.sh Infrastructure/ci/tests/validate-gitflow_test.sh
git commit -m "ci: enforce GitFlow pull request policy"
```

### Task 3: Implement self-hosted iOS runner preflight

**Files:**
- Create: `Infrastructure/ci/preflight-ios-runner.sh`
- Test: `Infrastructure/ci/tests/preflight-ios-runner_test.sh`

**Interfaces:**
- Consumes: `EXPECTED_XCODE_VERSION=26.6`, mise tool pins, and `IOS_SIMULATOR_NAME` defaulting to `iPhone 17`.
- Produces: validated Xcode, Tuist, SwiftLint, Docker, architecture, and Simulator environment.

- [ ] **Step 1: Write failing fixture-based tests**

Add command overrides `XCODEBUILD_BIN`, `MISE_BIN`, `DOCKER_BIN`, and `XCRUN_BIN`. Test one valid fixture and failures for wrong architecture, wrong Xcode version, and missing Simulator.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/preflight-ios-runner_test.sh`

Expected: FAIL because the preflight script is absent.

- [ ] **Step 3: Implement preflight checks**

The script must use `set -euo pipefail`, require `arm64`, compare `xcodebuild -version`, run `mise install`, verify `tuist version` and `swiftlint version`, call `docker info`, and search `xcrun simctl list devices available` for the configured Simulator.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
bash Infrastructure/ci/tests/preflight-ios-runner_test.sh
bash -n Infrastructure/ci/preflight-ios-runner.sh
```

Expected: all fixture cases pass.

- [ ] **Step 5: Commit**

```bash
git add Infrastructure/ci/preflight-ios-runner.sh Infrastructure/ci/tests/preflight-ios-runner_test.sh
git commit -m "ci: add iOS runner preflight"
```

### Task 4: Implement fail-closed SonarQube preflight

**Files:**
- Create: `Infrastructure/ci/preflight-sonarqube.sh`
- Test: `Infrastructure/ci/tests/preflight-sonarqube_test.sh`

**Interfaces:**
- Consumes: `SONAR_HOST_URL`, `SONAR_TOKEN`, and optional `CURL_BIN` override.
- Produces: exit `0` only when credentials exist and `/api/system/status` reports `UP`.

- [ ] **Step 1: Write failing tests**

Test missing URL, missing token, unreachable server, `STARTING` status, and `UP` status. Ensure captured output never contains the token fixture `secret-token-value`.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/preflight-sonarqube_test.sh`

Expected: FAIL because the implementation is absent.

- [ ] **Step 3: Implement minimal preflight**

Parse the response without printing headers or token:

```bash
response="$($CURL_BIN --fail --silent --show-error "$SONAR_HOST_URL/api/system/status")"
[[ "$response" == *'"status":"UP"'* ]] || fail "SonarQube is not UP"
```

- [ ] **Step 4: Verify GREEN and secret redaction**

Run: `bash Infrastructure/ci/tests/preflight-sonarqube_test.sh`

Expected: all five cases pass and the secret fixture is absent from output.

- [ ] **Step 5: Commit**

```bash
git add Infrastructure/ci/preflight-sonarqube.sh Infrastructure/ci/tests/preflight-sonarqube_test.sh
git commit -m "ci: add fail-closed SonarQube preflight"
```

### Task 5: Add local workflow validation

**Files:**
- Create: `.yamllint.yml`
- Create: `Infrastructure/ci/validate-workflows.sh`
- Test: `Infrastructure/ci/tests/validate-workflows_test.sh`

**Interfaces:**
- Consumes: `.github/workflows/*.yml` and CI shell scripts.
- Produces: a single local validation command with deterministic diagnostics.

- [ ] **Step 1: Write the failing contract**

The test creates one invalid YAML fixture and one invalid shell fixture, verifies each is rejected, then validates repository files.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/validate-workflows_test.sh`

Expected: FAIL because the validator does not exist.

- [ ] **Step 3: Implement validator**

Use installed `actionlint` and `yamllint`, then run `bash -n` over files returned by:

```bash
find Infrastructure/ci -type f -name '*.sh' -not -path '*/tests/fixtures/*' -print0
```

- [ ] **Step 4: Verify GREEN**

Run: `bash Infrastructure/ci/tests/validate-workflows_test.sh`

Expected: invalid fixtures fail and repository validation succeeds.

- [ ] **Step 5: Commit**

```bash
git add .yamllint.yml Infrastructure/ci/validate-workflows.sh Infrastructure/ci/tests/validate-workflows_test.sh
git commit -m "ci: validate workflows locally"
```

### Task 6: Add reusable PR policy workflow

**Files:**
- Create: `.github/workflows/pr-policy.yml`

**Interfaces:**
- Consumes: `workflow_call` inputs `base_ref`, `head_ref`, `is_draft`, and `pr_title`.
- Produces: stable job check name `PR Policy`.

- [ ] **Step 1: Add a failing workflow assertion**

Extend `validate-workflows_test.sh` to require `pr-policy.yml`, `workflow_call`, minimal `permissions: contents: read`, and the job name `PR Policy`.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/validate-workflows_test.sh`

Expected: FAIL because `pr-policy.yml` is absent.

- [ ] **Step 3: Add the workflow**

Use `ubuntu-24.04`, immutable `actions/checkout` SHA `34e114876b0b11c390a56381ad16ebd13914f8d5`, and pass inputs to `Infrastructure/ci/validate-gitflow.sh`. Add `workflow_dispatch` with equivalent inputs for diagnostics.

- [ ] **Step 4: Verify GREEN**

Run: `bash Infrastructure/ci/validate-workflows.sh`

Expected: actionlint, yamllint, and policy assertions pass.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/pr-policy.yml Infrastructure/ci/tests/validate-workflows_test.sh
git commit -m "ci: add pull request policy workflow"
```

### Task 7: Add reusable backend workflow

**Files:**
- Create: `.github/workflows/backend.yml`

**Interfaces:**
- Consumes: checked-out Go module under `Backend/`.
- Produces: stable job check name `Backend` and `Backend/coverage.out` artifact.

- [ ] **Step 1: Add failing structural assertions**

Require `workflow_call`, `ubuntu-24.04`, `gofmt`, `go vet`, `staticcheck`, `go test -race`, and `-coverprofile=coverage.out`.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/validate-workflows_test.sh`

Expected: FAIL because `backend.yml` is absent.

- [ ] **Step 3: Add backend workflow**

Pin checkout and setup-go actions by full SHA, cache with setup-go, install `honnef.co/go/tools/cmd/staticcheck@2025.1.1`, verify `gofmt -l` is empty, and run commands from `Backend/`.

- [ ] **Step 4: Verify locally**

Run:

```bash
cd Backend && mise exec -- gofmt -w . && go vet ./... && go test -race -coverprofile=coverage.out ./...
bash Infrastructure/ci/validate-workflows.sh
```

Expected: Go checks and workflow validation pass.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/backend.yml Infrastructure/ci/tests/validate-workflows_test.sh
git commit -m "ci: add backend quality workflow"
```

### Task 8: Add reusable iOS workflow

**Files:**
- Create: `.github/workflows/ios.yml`

**Interfaces:**
- Consumes: self-hosted runner labels and Makefile iOS commands.
- Produces: stable job check name `iOS` and failure diagnostics.

- [ ] **Step 1: Add failing structural assertions**

Require all four runner labels, `preflight-ios-runner.sh`, `swiftlint lint --strict`, package tests, full `CommerceApp` tests, unsigned build, and `timeout-minutes: 45`.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/validate-workflows_test.sh`

Expected: FAIL because `ios.yml` is absent.

- [ ] **Step 3: Add iOS workflow**

Use a concurrency group derived from `github.event.pull_request.number || github.ref`, run preflight before tool use, boot `iPhone 17`, execute existing Makefile targets, and upload `.xcresult` only on failure with a seven-day retention.

- [ ] **Step 4: Verify locally on the Mac**

Run:

```bash
Infrastructure/ci/preflight-ios-runner.sh
make ios-test-packages
make ios-build-unsigned
bash Infrastructure/ci/validate-workflows.sh
```

Expected: preflight, tests, unsigned build, and workflow validation pass.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ios.yml Infrastructure/ci/tests/validate-workflows_test.sh
git commit -m "ci: add self-hosted iOS workflow"
```

### Task 9: Add reusable security workflow

**Files:**
- Create: `.github/workflows/security.yml`

**Interfaces:**
- Consumes: repository source and PR base/head metadata.
- Produces: stable job check name `Security`, SARIF results, and CycloneDX SBOM.

- [ ] **Step 1: Add failing structural assertions**

Require CodeQL, dependency review, Gitleaks, Trivy, SBOM, `security-events: write`, and immutable SHA syntax for every `uses:` entry.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/validate-workflows_test.sh`

Expected: FAIL because `security.yml` is absent.

- [ ] **Step 3: Add security workflow**

Separate scan jobs so dependency review runs only for pull requests. Configure Gitleaks and Trivy to fail on high/critical findings, generate `sbom.cdx.json`, and retain sanitized artifacts for seven days.

- [ ] **Step 4: Verify workflow and local secret scan**

Run:

```bash
bash Infrastructure/ci/validate-workflows.sh
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:latest detect --source=/repo --no-banner
```

Expected: workflow validation and secret scan pass.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/security.yml Infrastructure/ci/tests/validate-workflows_test.sh
git commit -m "ci: add security scanning workflow"
```

### Task 10: Configure SonarQube project mapping

**Files:**
- Create: `sonar-project.properties`
- Test: `Infrastructure/ci/tests/sonar_config_test.sh`

**Interfaces:**
- Consumes: `Backend/coverage.out` and `Build/reports/swift-coverage.xml`.
- Produces: Sonar project key `learning-superpower` with Go and Swift source/test mapping.

- [ ] **Step 1: Write failing property assertions**

Require project key/name, UTF-8, source/test roots, exclusions for generated/build files, Go coverage path, Swift coverage path, and no embedded URL/token.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/sonar_config_test.sh`

Expected: FAIL because `sonar-project.properties` is absent.

- [ ] **Step 3: Add exact properties**

Use:

```properties
sonar.projectKey=learning-superpower
sonar.projectName=Learning Superpower Commerce
sonar.sourceEncoding=UTF-8
sonar.sources=Backend,Apps,Packages
sonar.tests=Backend,Apps,Packages
sonar.go.coverage.reportPaths=Backend/coverage.out
sonar.coverageReportPaths=Build/reports/swift-coverage.xml
sonar.exclusions=**/.build/**,**/Derived/**,**/*.xcodeproj/**,**/*.xcworkspace/**
```

- [ ] **Step 4: Verify GREEN**

Run: `bash Infrastructure/ci/tests/sonar_config_test.sh`

Expected: all mapping and secret assertions pass.

- [ ] **Step 5: Commit**

```bash
git add sonar-project.properties Infrastructure/ci/tests/sonar_config_test.sh
git commit -m "ci: configure SonarQube analysis"
```

### Task 11: Add reusable SonarQube workflow

**Files:**
- Create: `.github/workflows/quality.yml`

**Interfaces:**
- Consumes: repository variable `SONAR_HOST_URL`, secret `SONAR_TOKEN`, and coverage artifacts.
- Produces: stable job check name `SonarQube` with fail-closed Quality Gate result.

- [ ] **Step 1: Add failing structural assertions**

Require self-hosted runner labels, preflight, explicit secret/variable mapping, scanner invocation, and `sonar.qualitygate.wait=true`.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/validate-workflows_test.sh`

Expected: FAIL because `quality.yml` is absent.

- [ ] **Step 3: Add workflow**

Run Go coverage, iOS coverage export/conversion, `preflight-sonarqube.sh`, and the pinned SonarSource scanner action. Pass the token only through the action environment and never echo it.

- [ ] **Step 4: Verify locally**

Run:

```bash
SONAR_HOST_URL=http://localhost:9000 SONAR_TOKEN="$SONAR_TOKEN" Infrastructure/ci/preflight-sonarqube.sh
bash Infrastructure/ci/validate-workflows.sh
```

Expected: local server reports UP and workflow validation passes.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/quality.yml Infrastructure/ci/tests/validate-workflows_test.sh
git commit -m "ci: add strict SonarQube workflow"
```

### Task 12: Add aggregate CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: reusable workflows from Tasks 6–9 and 11.
- Produces: stable required check `Quality Gate` for PRs, protected-branch pushes, and manual runs.

- [ ] **Step 1: Add failing orchestration assertions**

Require triggers for PRs targeting `main`/`develop`, pushes to `main`/`develop`, `workflow_dispatch`, concurrency cancellation, all five reusable workflow calls, and a final `if: always()` gate.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/validate-workflows_test.sh`

Expected: FAIL because `ci.yml` is absent.

- [ ] **Step 3: Add orchestration**

Pass PR metadata to policy. The final job must fail unless every required `needs.<job>.result` equals `success`:

```bash
test '${{ needs.policy.result }}' = success
test '${{ needs.backend.result }}' = success
test '${{ needs.ios.result }}' = success
test '${{ needs.security.result }}' = success
test '${{ needs.sonarqube.result }}' = success
```

- [ ] **Step 4: Verify GREEN**

Run: `bash Infrastructure/ci/validate-workflows.sh`

Expected: all workflow contracts and linters pass.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml Infrastructure/ci/tests/validate-workflows_test.sh
git commit -m "ci: aggregate strict quality gates"
```

### Task 13: Add Sourcery review standards

**Files:**
- Create: `.sourcery.yaml`
- Create: `docs/development/sourcery-review-rules.md`
- Test: `Infrastructure/ci/tests/sourcery_config_test.sh`

**Interfaces:**
- Consumes: Sourcery GitHub App already installed for the repository.
- Produces: minimal valid legacy YAML plus an auditable, copy-ready record of Dashboard rules covering Swift, architecture, Go, OWASP, and tests. The Dashboard is the source of truth for active AI review rules.

- [ ] **Step 1: Write failing config assertions**

Require five documented Dashboard rules with their exact path globs and three-blocking/two-nonblocking split. Require guidance containing `Swift 6`, `MainActor`, `Clean Architecture`, `MVVM-C`, `Factory`, `XCoordinator`, `Go`, `JWT`, `OWASP`, and `regression test`; validate the meaningful minimal legacy YAML schema and reject secrets and unsupported source exclusions.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/sourcery_config_test.sh`

Expected: FAIL because the required Sourcery artifact is absent.

- [ ] **Step 3: Add standards**

Keep `.sourcery.yaml` minimal and valid under the published legacy schema. Record the Dashboard rules in `docs/development/sourcery-review-rules.md`, including exact paths and blocking states, setup and reload verification, actionable file/line evidence, correctness/security/data-race priorities, and suppression of formatting feedback already covered by SwiftLint/gofmt. Do not represent Markdown or YAML comments as active configuration.

- [ ] **Step 4: Verify GREEN**

Run: `bash Infrastructure/ci/tests/sourcery_config_test.sh`

Expected: all five Dashboard rules and blocking states are present, minimal YAML is valid, and no secret or unsupported exclusion pattern is found.

- [ ] **Step 5: Commit**

```bash
git add .sourcery.yaml docs/development/sourcery-review-rules.md Infrastructure/ci/tests/sourcery_config_test.sh docs/superpowers/specs/2026-07-12-gitflow-cicd-design.md docs/superpowers/plans/2026-07-12-gitflow-cicd.md
git commit -m "ci: configure Sourcery review standards"
```

### Task 14: Add CI Makefile commands

**Files:**
- Modify: `Makefile`
- Test: `Infrastructure/ci/tests/makefile_ci_test.sh`

**Interfaces:**
- Consumes: validation, backend, iOS, and security scripts/workflows.
- Produces: `ci-validate`, `ci-backend`, `ci-ios`, `ci-security`, and `ci-all` targets.

- [ ] **Step 1: Write failing target assertions**

Run `make -n` for every target and assert the expected underlying commands are present. Assert `ci-all` depends on the four component targets.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/makefile_ci_test.sh`

Expected: FAIL because CI targets do not exist.

- [ ] **Step 3: Add targets**

`ci-validate` runs workflow and config contracts; `ci-backend` runs fmt/vet/race/coverage; `ci-ios` runs preflight/lint/tests/unsigned build; `ci-security` runs local Gitleaks and Trivy checks; `ci-all` composes them.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
bash Infrastructure/ci/tests/makefile_ci_test.sh
make ci-validate
```

Expected: Makefile contract and validation pass.

- [ ] **Step 5: Commit**

```bash
git add Makefile Infrastructure/ci/tests/makefile_ci_test.sh
git commit -m "ci: add local quality gate commands"
```

### Task 15: Write CI/CD operations runbook

**Files:**
- Create: `docs/development/gitflow-cicd.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: exact workflows, scripts, runner labels, variables, and secrets created above.
- Produces: reproducible setup and recovery instructions.

- [ ] **Step 1: Add documentation contract**

Extend `validate-workflows_test.sh` to require commands for runner registration/service lifecycle, `SONAR_HOST_URL`, `SONAR_TOKEN`, branch creation, ruleset verification, Sourcery trigger, queued-run recovery, Simulator recovery, and secret rotation.

- [ ] **Step 2: Verify RED**

Run: `bash Infrastructure/ci/tests/validate-workflows_test.sh`

Expected: FAIL because the runbook is absent.

- [ ] **Step 3: Write runbook and README link**

Include exact safe commands using placeholders such as shell environment variable names, never realistic credential values. Document that runner registration tokens are short-lived and must be obtained from repository Settings.

- [ ] **Step 4: Verify docs**

Run:

```bash
bash Infrastructure/ci/validate-workflows.sh
rg -n "gitflow-cicd.md" README.md
```

Expected: documentation contract passes and README links the runbook.

- [ ] **Step 5: Commit**

```bash
git add docs/development/gitflow-cicd.md README.md Infrastructure/ci/tests/validate-workflows_test.sh
git commit -m "docs: add GitFlow CI/CD runbook"
```

### Task 16: Publish and configure GitHub repository gates

**Files:**
- No repository file changes expected.

**Interfaces:**
- Consumes: pushed workflow commits, GitHub admin API, installed Sourcery App, self-hosted runner, `SONAR_HOST_URL`, and `SONAR_TOKEN`.
- Produces: `develop`, configured Actions values, observed check names, strict rulesets, and Sourcery review on PR #3.

- [ ] **Step 1: Run final local verification**

Run:

```bash
make ci-validate
make ci-backend
make ci-ios
make ci-security
git diff --check
git status --short
```

Expected: every command exits `0` and the worktree is clean.

- [ ] **Step 2: Push feature branch and update PR #3**

```bash
git push origin feat/phase-02-ios-platform
gh pr view 3 --json url,headRefOid,statusCheckRollup
```

Expected: PR head equals local HEAD and workflow checks appear.

- [ ] **Step 3: Create and push `develop` from `main`**

```bash
git fetch origin main
git branch develop origin/main
git push -u origin develop
```

Expected: `origin/develop` points to the current `origin/main` commit.

- [ ] **Step 4: Verify Actions configuration without exposing values**

Use `gh variable list` to confirm `SONAR_HOST_URL`, `gh secret list` to confirm `SONAR_TOKEN`, and `gh api repos/jerry-nows/learning-superpower/actions/runners` to confirm an online runner with all four labels. If any prerequisite is absent, stop and report the exact Settings action required; do not weaken the gate.

- [ ] **Step 5: Observe exact successful check contexts**

Run:

```bash
gh pr checks 3 --watch
gh pr view 3 --json statusCheckRollup,reviews,comments
```

Expected: PR Policy, Backend, iOS, Security, SonarQube, and Quality Gate complete successfully.

- [ ] **Step 6: Trigger and observe Sourcery**

```bash
gh pr comment 3 --body '@sourcery-ai review'
```

Poll PR reviews/checks until the Sourcery App appears. Record its exact check context; do not guess it.

- [ ] **Step 7: Apply strict rulesets through GitHub API**

Create rulesets for `refs/heads/main` and `refs/heads/develop` requiring the observed contexts, one approval, dismissal of stale reviews, resolved conversations, linear history, and blocking deletion/force-push. Set bypass actors to an empty list. If the private repository plan rejects a rule type, stop and report the GitHub plan limitation rather than applying a weaker configuration.

- [ ] **Step 8: Verify enforcement**

Read both rulesets back with `gh api`, compare every required check context and rule, and verify PR #3 reports the expected blocking state while it remains a draft or lacks approval.

---

### Task 16A: Migrate public-PR CI to hosted services

**Approved variance:** Replace the personal self-hosted Mac and local SonarQube dependency for pull-request CI with GitHub-hosted `macos-26` runners and SonarQube Cloud Free. Never register or expose a personal runner to public pull-request code. Keep the loopback-only Docker SonarQube stack as optional local development tooling, not a CI prerequisite.

**Files:**
- Modify: `.github/workflows/ios.yml`, `.github/workflows/quality.yml`, `.github/workflows/ci.yml`, `sonar-project.properties`
- Modify: `Infrastructure/ci/tests/validate-workflows_test.sh`, `Infrastructure/ci/tests/sonar_config_test.sh`
- Modify: `docs/superpowers/specs/2026-07-12-gitflow-cicd-design.md`, affected Phase 02B CR records, and `docs/development/gitflow-cicd.md`

**Implementation:**
1. Change workflow contracts first and capture RED evidence for hosted macOS, Xcode 26.6 selection, SonarQube Cloud project identity, token-only scanner configuration, and safe fork behavior.
2. Run iOS and SonarQube coverage/analysis on GitHub-hosted `macos-26`; configure `sonar.organization=jerry-nows` and `sonar.projectKey=jerry-nows_learning-superpower`; pass only `SONAR_TOKEN`; wait synchronously for the Quality Gate.
3. For same-repository PRs and protected-branch pushes, fail closed when the token or Cloud project is unavailable. For fork pull requests, do not use `pull_request_target` or expose secrets: skip the scanner explicitly, surface a non-successful SonarQube result, and keep aggregate `Quality Gate` blocked.
4. Retain local Docker SonarQube and its preflight only as optional developer tooling, update architecture/CR/runbook guidance, and verify workflow contracts, Sonar mappings, actionlint, yamllint, and whitespace.

**Definition of Done:** Public pull-request code executes only on fresh GitHub-hosted runners; privileged SonarQube Cloud analysis receives only `SONAR_TOKEN` on trusted events; fork PRs cannot access secrets or satisfy the aggregate gate; no CI job depends on `SONAR_HOST_URL`, a personal runner, or local Docker.

---

## Final Verification Matrix

| Requirement | Evidence |
|---|---|
| GitFlow branch pairs | `validate-gitflow_test.sh` |
| Workflow syntax and immutable actions | `validate-workflows.sh` |
| Backend gate | `make ci-backend` and GitHub `Backend` check |
| iOS gate | `make ci-ios` and GitHub `iOS` check |
| Security gate | GitHub `Security` check and uploaded reports |
| Sonar fail-closed gate | `preflight-sonarqube_test.sh` and GitHub `SonarQube` check |
| Aggregate gate | GitHub `Quality Gate` check |
| Sourcery review | PR #3 review/check from Sourcery App |
| Branch protection | GitHub ruleset API read-back |
| Operations recovery | `docs/development/gitflow-cicd.md` contract |
