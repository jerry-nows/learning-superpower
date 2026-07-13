# GitFlow CI/CD operations

This runbook operates the strict GitFlow pipeline in `.github/workflows/ci.yml`. The aggregate `Quality Gate` succeeds only when PR Policy, Backend, iOS, Security, and SonarQube all succeed. Required checks, unavailable infrastructure, and missing configuration **fail closed**: repair the prerequisite; never remove, skip, or make a required gate advisory.

## Prerequisites and exact execution topology

- PR Policy, Backend, Security, and the aggregate Quality Gate use `ubuntu-24.04` GitHub-hosted runners.
- iOS and SonarQube use `runs-on: [self-hosted, macOS, ARM64, commerce-ios]` on an Apple Silicon Mac.
- The Mac must provide Xcode 26.6, Tuist 4.202.1 and SwiftLint 0.65.0 through `mise`, Docker, and an available `iPhone 17` Simulator. Validate it with `Infrastructure/ci/preflight-ios-runner.sh`.
- Install `gh`, authenticate as a repository administrator, and set a safe repository selector:

```bash
export GITHUB_REPOSITORY="OWNER/REPOSITORY"
export REPOSITORY_URL="https://github.com/$GITHUB_REPOSITORY"
gh auth status
```

Do not paste credentials into this file, shell history, command arguments, logs, or issue comments.

## Register and operate the macOS runner

In repository **Settings > Actions > Runners**, choose **New self-hosted runner**, macOS, ARM64, and follow GitHub's current download/checksum commands. Runner registration tokens are short-lived and must be obtained from that repository Settings page. Put the token in an environment variable only for registration; the placeholder below is not a credential.

From the extracted runner directory:

```bash
read -rs RUNNER_REGISTRATION_TOKEN
export RUNNER_REGISTRATION_TOKEN
./config.sh --url "$REPOSITORY_URL" --token "$RUNNER_REGISTRATION_TOKEN" --labels commerce-ios
unset RUNNER_REGISTRATION_TOKEN
./svc.sh install
./svc.sh start
./svc.sh status
```

GitHub supplies the `self-hosted`, `macOS`, and `ARM64` labels; registration adds `commerce-ios`. Confirm all four labels and online status without exposing tokens:

```bash
gh api "repos/$GITHUB_REPOSITORY/actions/runners" --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
```

For maintenance, drain work first, then run these commands from the runner directory:

```bash
./svc.sh stop
./svc.sh status
./svc.sh uninstall
```

Use uninstall only when removing or re-registering the runner. Obtain a new short-lived registration/removal token from Settings; never reuse or record an old one.

## Configure SonarQube

`SONAR_HOST_URL` is a repository Actions variable. `SONAR_TOKEN` is a repository Actions secret and is mapped only into the SonarQube preflight and scanner environments. The workflow waits synchronously with `-Dsonar.qualitygate.wait=true`.

```bash
export SONAR_HOST_URL="https://sonarqube.example.invalid"
gh variable set SONAR_HOST_URL --body "$SONAR_HOST_URL"
read -rs SONAR_TOKEN
export SONAR_TOKEN
printf '%s' "$SONAR_TOKEN" | gh secret set SONAR_TOKEN
unset SONAR_TOKEN
gh variable list | grep -F SONAR_HOST_URL
gh secret list | grep -F SONAR_TOKEN
```

Replace the deliberately invalid URL with the runner-reachable SonarQube URL. Test from the runner without printing the token:

```bash
read -rs SONAR_TOKEN
export SONAR_TOKEN
Infrastructure/ci/preflight-sonarqube.sh
unset SONAR_TOKEN
```

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
gh api "repos/$GITHUB_REPOSITORY/rulesets"
for RULESET_ID in $(gh api "repos/$GITHUB_REPOSITORY/rulesets" --jq '.[].id'); do
  gh api "repos/$GITHUB_REPOSITORY/rulesets/$RULESET_ID" \
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

### Queued self-hosted jobs

If iOS or SonarQube remains queued, inspect the runner API and `./svc.sh status`. Confirm the runner is online, idle, and has `self-hosted`, `macOS`, `ARM64`, and `commerce-ios`. Start the service if stopped. After the prerequisite is healthy, rerun only failed jobs:

```bash
export RUN_ID="FAILED_RUN_ID"
gh run view "$RUN_ID" --log-failed
gh run rerun "$RUN_ID" --failed
gh run watch "$RUN_ID" --exit-status
```

Do not change `runs-on` labels or remove the required check to clear a queue. New commits cancel superseded PR runs by design; rerun the latest commit only.

### Simulator

Run the iOS preflight first. If `iPhone 17` is unavailable or stuck, confirm Xcode 26.6 is selected, then reset Simulator state:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcrun simctl shutdown all
xcrun simctl erase all
xcrun simctl list devices available
xcrun simctl boot "iPhone 17"
xcrun simctl bootstatus "iPhone 17" -b
Infrastructure/ci/preflight-ios-runner.sh
```

Erasing removes Simulator data. If the device type/runtime is absent, install the required runtime through Xcode before rerunning; do not substitute a different destination in CI.

### Docker and SonarQube

If Docker is unavailable, start it and wait for the engine:

```bash
open -a Docker
until docker info >/dev/null 2>&1; do sleep 2; done
```

From the directory containing the approved Compose file, recover and inspect SonarQube:

```bash
docker compose up -d sonarqube
docker compose ps
docker compose logs --tail=100 sonarqube
curl --fail --silent --show-error "$SONAR_HOST_URL/api/system/status"
```

Wait for status `UP`, then run `Infrastructure/ci/preflight-sonarqube.sh`. Never bypass synchronous Quality Gate waiting.

## Rotate credentials

Rotate `SONAR_TOKEN` immediately after suspected disclosure and on the team's schedule: create a new least-privilege token in SonarQube, update GitHub through masked standard input, validate a CI run, then revoke the old token.

```bash
read -rs SONAR_TOKEN
export SONAR_TOKEN
printf '%s' "$SONAR_TOKEN" | gh secret set SONAR_TOKEN
unset SONAR_TOKEN
gh secret list | grep -F SONAR_TOKEN
```

**Rotate SONAR_TOKEN** without changing its name. Runner registration tokens are already short-lived; for runner credential rotation, remove the runner in Settings, stop/uninstall its service, delete its local credentials according to GitHub's removal instructions, and register it again with a newly issued Settings token. Reverify online status and all four labels before accepting jobs.

## Repository verification

```bash
bash Infrastructure/ci/validate-workflows.sh
bash Infrastructure/ci/tests/validate-workflows_test.sh
bash Infrastructure/ci/tests/sourcery_config_test.sh
```
