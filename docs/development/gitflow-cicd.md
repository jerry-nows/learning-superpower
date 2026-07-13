# GitFlow CI/CD operations

This runbook operates the strict GitFlow pipeline in `.github/workflows/ci.yml`. The aggregate `Quality Gate` succeeds only when PR Policy, Backend, iOS, Security, and SonarQube all succeed. Required checks, unavailable infrastructure, and missing configuration **fail closed**: repair the prerequisite; never remove, skip, or make a required gate advisory.

## Prerequisites and exact execution topology

- PR Policy, Backend, Security, and the aggregate Quality Gate use `ubuntu-24.04` GitHub-hosted runners.
- iOS and SonarQube use `runs-on: macos-26` on fresh GitHub-hosted Apple Silicon virtual machines. The workflows explicitly select Xcode 26.6 because the image default may differ.
- The hosted jobs install Tuist 4.202.1 and SwiftLint 0.65.0 through `mise` and require an available `iPhone 17` Simulator. Validate the toolchain with `Infrastructure/ci/preflight-ios-runner.sh`.
- Install `gh`, authenticate as a repository administrator, and set a safe repository selector:

```bash
export GH_REPO="jerry-nows/learning-superpower"
export REPOSITORY_URL="https://github.com/$GH_REPO"
gh auth status
```

Do not paste credentials into this file, shell history, command arguments, logs, or issue comments.

## Hosted-runner safety

Never register a personal self-hosted runner for this public repository. Pull-request code executes only on GitHub-hosted virtual machines with read-only repository permissions unless a narrowly scoped job explicitly needs more. In particular, do not use `pull_request_target` to check out or execute a fork's code with repository credentials.

## Configure SonarQube for OSS

Create or import one SonarQube for OSS project for the repository with `sonar.organization=jerry-nows` and `sonar.projectKey=jerry-nows_learning-superpower`. The Free plan analyzes pull requests only when they target `main`; it is incompatible with the mandatory `feature/* -> develop` path and would leave integration PRs without analysis. SonarQube for OSS supports this public multi-branch GitFlow, including `feature/* -> develop` and release/hotfix PRs to `main`, but only analyzes public repositories. If this repository becomes private, the OSS plan is no longer valid and CI must move to a plan that supports private repositories before merging further changes.

Although SonarSource recommends a project per independently built monorepo component, this repository deliberately uses one combined Swift-and-Go project: the repository ships as one quality unit, the existing scanner produces both coverage reports in one workspace, and one synchronous result gives the aggregate workflow a stable fail-closed dependency. Revisit the model if the components gain independent release lifecycles. SonarQube Cloud's native monorepo PR-blocking behavior must not be assumed to replace the repository's own `Quality Gate`. Keep Automatic Analysis off so the pinned CI scanner remains the sole analysis path.

`SONAR_TOKEN` is the only GitHub Actions secret required. SonarQube for OSS uses the dedicated analysis token with Execute Analysis permission for this project. The workflow waits synchronously with `-Dsonar.qualitygate.wait=true`; neither `SONAR_HOST_URL` nor the local preflight is used by cloud CI.

```bash
read -rs SONAR_TOKEN
export SONAR_TOKEN
printf '%s' "$SONAR_TOKEN" | gh secret set SONAR_TOKEN
unset SONAR_TOKEN
gh secret list | grep -F SONAR_TOKEN
```

Same-repository pull requests and protected-branch pushes fail immediately if the token is missing. GitHub withholds repository secrets from fork pull requests; the SonarQube job detects that case before building or scanning, emits an explicit error, and fails. The aggregate `Quality Gate` therefore remains blocked until a maintainer brings the contribution onto a trusted same-repository branch. It never reports an unexecuted scan as successful and never runs untrusted code with a secret.

## Create `develop` and follow GitFlow

Create `develop` from the current `main` before enabling its ruleset:

```bash
git fetch origin
git switch main
git pull --ff-only origin main
git switch -c develop main
git push -u origin develop
```

Allowed pull requests are `feature/* -> develop`, `release/* -> main`, and `hotfix/* -> main`. Draft PRs and titles that do not use Conventional Commits are rejected. Direct pushes to protected branches are not an operating procedure.

## CodeQL advanced setup for this public repository

The repository owns CodeQL configuration in `.github/workflows/security.yml` for Go on `ubuntu-24.04`, alongside Dependency Review, Gitleaks, Trivy, and CycloneDX SBOM generation. For this public repository, open **Settings > Code security > Code scanning**, **Disable default setup**, and retain **CodeQL advanced setup**. Do not run default and advanced setup together. Confirm the CodeQL check produced by `security.yml` before adding its observed context through the aggregate gate.

## Configure and verify strict rulesets

After a successful representative PR run, read exact check names from GitHub rather than guessing them. Protect `refs/heads/main` and `refs/heads/develop` with no bypass actors; require pull requests, one approval, dismissal of stale approvals, resolved conversations, linear history, and the observed required status checks. Block force pushes and deletion. Both rulesets must require the stable aggregate `Quality Gate` plus the observed Sourcery context once it exists. If GitHub rejects a required rule because of the repository plan, stop and report the limitation; do not weaken the policy.

Verify API read-back and inspect every rule, target, bypass list, and required context:

```bash
gh api "repos/$GH_REPO/rulesets"
for RULESET_ID in $(gh api "repos/$GH_REPO/rulesets" --jq '.[].id'); do
  gh api "repos/$GH_REPO/rulesets/$RULESET_ID" \
    --jq '{name,enforcement,target,conditions,bypass_actors,rules}'
done
```

Expected enforcement is `active`, branch targets are exactly `main` or `develop`, `bypass_actors` is empty, pull-request requirements are strict, and required contexts exactly match successful check runs.

## Sourcery Dashboard rules and PR #3

The Sourcery Dashboard is the source of truth for active review rules. The exact five-rule, three-blocking/two-nonblocking audit record is `docs/development/sourcery-review-rules.md`; `.sourcery.yaml` is only the minimal legacy configuration. Copy all five rules into the Dashboard, save, reload, and compare every path, instruction, and blocking state with the record.

Sourcery reviews new PRs automatically. After the CI configuration is pushed, trigger the approved existing PR #3:

```bash
gh pr comment 3 --body '@sourcery-ai review'
gh pr checks 3 --watch
```

Observe Sourcery's actual check context, then add exactly that context to both rulesets and repeat API verification. A missing Sourcery result blocks merging; verify App installation and repository access, reload the Dashboard rules, and retrigger rather than guessing a check name.

## Recovery without weakening gates

### Hosted workflow jobs

If iOS or SonarQube remains queued, inspect GitHub Actions service status, repository Actions availability, and concurrency. There is no repository runner service to register or start. After GitHub-hosted capacity is available, rerun only failed jobs:

```bash
export RUN_ID="FAILED_RUN_ID"
gh run view "$RUN_ID" --log-failed
gh run rerun "$RUN_ID" --failed
gh run watch "$RUN_ID" --exit-status
```

Do not change `runs-on: macos-26` or remove a required check to clear a queue. New commits cancel superseded PR runs by design; rerun the latest commit only.

### Simulator

Run the iOS preflight first. If `iPhone 17` is unavailable or stuck, confirm Xcode 26.6 is selected, then reset Simulator state:

```bash
sudo xcode-select -s /Applications/Xcode_26.6.app/Contents/Developer
xcrun simctl shutdown all
xcrun simctl erase all
xcrun simctl list devices available
xcrun simctl boot "iPhone 17"
xcrun simctl bootstatus "iPhone 17" -b
Infrastructure/ci/preflight-ios-runner.sh
```

Erasing removes Simulator data. If the device type/runtime is absent, install the required runtime through Xcode before rerunning; do not substitute a different destination in CI.

### Optional local Docker SonarQube

If Docker is unavailable, start it and wait for the engine:

```bash
open -a Docker
until docker info >/dev/null 2>&1; do sleep 2; done
```

The repository owns a dedicated persistent SonarQube/PostgreSQL stack at `Infrastructure/sonarqube.compose.yaml`. Its published port is intentionally bound as `127.0.0.1:${SONAR_PORT:-9000}:9000`, so only a runner on the Docker host can connect directly. From the repository root, first create a local environment file and replace every `change-me` value. Never commit `.env`:

```bash
cp .env.example .env
${EDITOR:-vi} .env
docker compose --env-file .env -f Infrastructure/sonarqube.compose.yaml config --quiet
docker compose --env-file .env -f Infrastructure/sonarqube.compose.yaml up -d --wait sonarqube
docker compose --env-file .env -f Infrastructure/sonarqube.compose.yaml ps
docker compose --env-file .env -f Infrastructure/sonarqube.compose.yaml logs --tail=100 sonarqube
curl --fail --silent --show-error "$SONAR_HOST_URL/api/system/status"
```

Set `SONAR_HOST_URL=http://127.0.0.1:${SONAR_PORT:-9000}` only for local development. Wait for status `UP`, then run `Infrastructure/ci/preflight-sonarqube.sh`. This stack and preflight never participate in pull-request CI.

Do not expose the optional local service to CI. If a separate remote development client must access SonarQube, do not change the Compose mapping to `0.0.0.0` or another all-interface binding. Keep the direct service loopback-only and place an authenticated reverse proxy on the Docker host in front of it. Require TLS with a trusted certificate, restrict the host firewall to the remote client's stable source address and the proxy's TLS port, and ensure the proxy is the only permitted route to SonarQube.

After the first local start, immediately replace the bootstrap administrator password and create a dedicated least-privilege analysis token for local use. Do not reuse the administrator password or the SonarQube Cloud token. Stop without deleting persistent data with:

```bash
docker compose --env-file .env -f Infrastructure/sonarqube.compose.yaml stop
```

Recover a stopped or unhealthy stack with `up -d --wait`, `ps`, and `logs` above. If the database volume is damaged, back it up before any destructive action. `docker compose ... down --volumes` permanently removes analysis history and is not a routine recovery command. Never bypass synchronous Quality Gate waiting.

### Generated coverage cleanup

`Backend/coverage.out` is generated by backend and SonarQube coverage runs and is ignored by Git. Remove only that known generated file from the repository root when cleaning local CI output:

```bash
rm -f Backend/coverage.out
```

## Rotate credentials

Rotate `SONAR_TOKEN` immediately after suspected disclosure and on the team's schedule: create a new least-privilege token in SonarQube, update GitHub through masked standard input, validate a CI run, then revoke the old token.

```bash
read -rs SONAR_TOKEN
export SONAR_TOKEN
printf '%s' "$SONAR_TOKEN" | gh secret set SONAR_TOKEN
unset SONAR_TOKEN
gh secret list | grep -F SONAR_TOKEN
```

**Rotate SONAR_TOKEN** without changing its name. No personal runner credential exists or should be created for this public repository.

## Repository verification

```bash
bash Infrastructure/ci/validate-workflows.sh
bash Infrastructure/ci/tests/validate-workflows_test.sh
bash Infrastructure/ci/tests/sourcery_config_test.sh
```
