SHELL := /bin/bash
ENV_FILE ?= $(if $(wildcard .env),.env,.env.example)
COMPOSE := docker compose --env-file $(ENV_FILE) -f Infrastructure/compose.yaml

.PHONY: bootstrap certs infra-up infra-down infra-logs test-go test-foundation smoke

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
