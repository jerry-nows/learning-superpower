SHELL := /bin/bash
ENV_FILE ?= $(if $(wildcard .env),.env,.env.example)
COMPOSE := docker compose --env-file $(ENV_FILE) -f Infrastructure/compose.yaml
IOS_WORKSPACE := Commerce.xcworkspace
IOS_SCHEME := CommerceApp
IOS_SIMULATOR_DESTINATION ?= platform=iOS Simulator,name=iPhone 17

.PHONY: bootstrap certs infra-up infra-down infra-logs test-go test-foundation smoke \
	ios-generate ios-test-packages ios-build-unsigned

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

test-go:
	@cd Backend && mise exec -- go test -race ./...

test-foundation:
	@bash Infrastructure/tests/check-tools_test.sh
	@bash Infrastructure/tests/compose_test.sh
	@bash Infrastructure/tests/certs_test.sh
	@bash Infrastructure/tests/smoke_test.sh

smoke:
	@ENV_FILE="$(CURDIR)/$(ENV_FILE)" Infrastructure/scripts/smoke.sh

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
