SHELL := /bin/bash
ENV_FILE ?= $(if $(wildcard .env),.env,.env.example)
COMPOSE_ENV_FILE := $(abspath $(ENV_FILE))
COMPOSE := docker compose --env-file $(COMPOSE_ENV_FILE) -f Infrastructure/compose.yaml
IOS_WORKSPACE := Commerce.xcworkspace
IOS_SCHEME := CommerceApp
IOS_SIMULATOR_DESTINATION ?= platform=iOS Simulator,name=iPhone 17

.PHONY: bootstrap certs infra-up infra-down infra-logs migrate seed auth-e2e test-go test-foundation smoke \
	ios-generate ios-test-packages ios-build-unsigned ci-validate ci-backend ci-ios \
	ci-security ci-all

bootstrap:
	@Infrastructure/scripts/check-tools.sh

certs:
	@set -a; source "$(ENV_FILE)"; set +a; Infrastructure/scripts/create-certs.sh

infra-up:
	@$(COMPOSE) up --build --wait

infra-down:
	@$(COMPOSE) down --remove-orphans

infra-logs:
	@$(COMPOSE) logs -f --tail=200

migrate:
	@$(COMPOSE) up --build --wait api

seed:
	@$(COMPOSE) run --rm --no-deps -T seed

auth-e2e: migrate seed
	@ENV_FILE="$(COMPOSE_ENV_FILE)" Infrastructure/scripts/auth-e2e.sh

test-go:
	@cd Backend && mise exec -- go test -race ./...

test-foundation:
	@bash Infrastructure/tests/check-tools_test.sh
	@bash Infrastructure/tests/compose_test.sh
	@bash Infrastructure/tests/certs_test.sh
	@bash Infrastructure/tests/smoke_test.sh

smoke:
	@ENV_FILE="$(COMPOSE_ENV_FILE)" Infrastructure/scripts/smoke.sh

ios-generate:
	@mise exec -- tuist generate --no-open

ios-test-packages:
	@cd Packages/Core && xcodebuild -scheme Core \
		-destination '$(IOS_SIMULATOR_DESTINATION)' test CODE_SIGNING_ALLOWED=NO
	@cd Packages/DesignSystem && xcodebuild -scheme DesignSystem \
		-destination '$(IOS_SIMULATOR_DESTINATION)' test CODE_SIGNING_ALLOWED=NO

ios-build-unsigned: ios-generate
	@xcodebuild -workspace $(IOS_WORKSPACE) -scheme $(IOS_SCHEME) \
		-destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

ci-validate:
	@bash Infrastructure/ci/tests/validate-gitflow_test.sh
	@bash Infrastructure/ci/tests/preflight-ios-runner_test.sh
	@bash Infrastructure/ci/tests/preflight-sonarqube_test.sh
	@bash Infrastructure/ci/tests/sonar_config_test.sh
	@bash Infrastructure/ci/tests/sourcery_config_test.sh
	@bash Infrastructure/ci/tests/xccov-to-sonarqube_test.sh
	@bash Infrastructure/ci/tests/validate-workflows_test.sh
	@bash Infrastructure/ci/tests/makefile_ci_test.sh

ci-backend:
	@cd Backend && unformatted="$$(mise exec -- gofmt -l .)"; \
		if [[ -n "$$unformatted" ]]; then \
			printf 'The following Go files require gofmt:\n%s\n' "$$unformatted" >&2; \
			exit 1; \
		fi
	@cd Backend && mise exec -- go vet ./...
	@cd Backend && mise exec -- go run honnef.co/go/tools/cmd/staticcheck@2025.1.1 ./...
	@cd Backend && mise exec -- go test -race -coverprofile=coverage.out ./...

ci-ios:
	@Infrastructure/ci/preflight-ios-runner.sh
	@mise exec -- swiftlint lint --strict
	@$(MAKE) ios-test-packages
	@mkdir -p TestResults
	@rm -rf TestResults/CommerceApp.xcresult
	@xcodebuild -workspace $(IOS_WORKSPACE) -scheme $(IOS_SCHEME) \
		-destination '$(IOS_SIMULATOR_DESTINATION)' \
		-resultBundlePath TestResults/CommerceApp.xcresult \
		test CODE_SIGNING_ALLOWED=NO
	@$(MAKE) ios-build-unsigned

ci-security:
	@docker run --rm -v "$(CURDIR):/repo:ro" zricethezav/gitleaks:v8.28.0 \
		detect --source=/repo --redact --no-banner
	@docker run --rm -v "$(CURDIR):/repo:ro" aquasec/trivy:0.66.0 \
		fs --scanners vuln --severity HIGH,CRITICAL --exit-code 1 /repo

ci-all: ci-validate ci-backend ci-ios ci-security
