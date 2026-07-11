# Foundation and Local Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a reproducible monorepo foundation and expose a tested Go health endpoint through locally trusted HTTPS while PostgreSQL, Redis, and Kafka run in Docker Compose.

**Architecture:** The first executable vertical slice is deliberately narrow: a dependency-free Go HTTP process owns liveness, Caddy terminates TLS, and Docker Compose owns service lifecycle. Tool versions, secrets boundaries, health checks, and developer commands are explicit so later iOS and backend modules build on stable infrastructure without changing these entry points.

**Tech Stack:** Go 1.26.5, Docker Compose v2, PostgreSQL 18.4, Redis 8.2, Apache Kafka 4.3.1 in KRaft mode, Caddy 2.10.0, mkcert, Make, GitHub Actions

## Global Constraints

- The repository remains a monorepo with `Apps/CommerceApp`, `Packages`, `Backend`, and `Infrastructure` top-level concerns.
- The iOS deployment floor is iOS 17+, UIKit, Swift 6 strict concurrency, Tuist, and local Swift Package Manager modules; iOS implementation begins in plan 2.
- The local stack must support both iOS Simulator and a physical iPhone on the same LAN.
- Generated certificates, private keys, tokens, passwords, and machine-specific addresses must never be committed.
- PostgreSQL is the future business source of truth; Redis may hold only sessions, rate limits, and disposable caches.
- Kafka runs in KRaft mode and stays outside synchronous HTTP response paths.
- No Apple Developer account, signing, archive, or IPA export is required.
- Every task leaves the branch testable and ends in a focused commit.

## File Structure

```text
.env.example                              Non-secret local defaults and pinned image tags
.github/workflows/foundation.yml          Foundation lint, unit, container, and smoke checks
.gitignore                                Generated local infrastructure exclusions
.mise.toml                                Go and infrastructure tool version contract
Makefile                                  Stable developer entry points
Backend/Dockerfile                        Reproducible non-root API image
Backend/go.mod                            Go module and language version
Backend/cmd/api/main.go                   Process lifecycle and HTTP server wiring
Backend/internal/health/handler.go        Liveness handler
Backend/internal/health/handler_test.go   HTTP contract tests
Infrastructure/Caddyfile                  Local HTTPS reverse proxy
Infrastructure/compose.yaml               PostgreSQL, Redis, Kafka, API, and Caddy topology
Infrastructure/scripts/check-tools.sh     Bootstrap preflight
Infrastructure/scripts/create-certs.sh    mkcert generation without committing secrets
Infrastructure/scripts/smoke.sh           End-to-end HTTPS and dependency verification
Infrastructure/tests/check-tools_test.sh  Preflight behavior tests
Infrastructure/tests/compose_test.sh      Compose contract checks
Infrastructure/tests/certs_test.sh        Certificate script behavior tests
Infrastructure/tests/smoke_test.sh        Smoke script failure/success tests
docs/development/local-setup.md            Trust and startup instructions
```

## Plan Series Coverage

This document is plan 1 of 7. Requirements intentionally deferred from this independently executable foundation slice are assigned as follows:

1. This plan: repository contract, Go liveness, PostgreSQL, Redis, Kafka, Caddy, trusted local TLS, smoke tests, and foundation CI.
2. `ios-platform-design-system`: Tuist workspace, shared SPM packages, Factory composition, XCoordinator root, Core Data base, networking/security/connectivity primitives, and Editorial Minimal UIKit components.
3. `authentication-end-to-end`: seeded credentials, Argon2id, 60-second JWT access token, refresh rotation/reuse detection, Keychain, Face ID, login/logout, and single-flight refresh.
4. `catalog-end-to-end`: categories, cursor pagination, refresh, debounced search, filters, sorting, Core Data query cache, bilingual VND presentation.
5. `product-detail-connectivity`: parallel section APIs, progressive skeleton rendering, typed section errors, offline banner, lifecycle-aware resume.
6. `cart-checkout-events`: per-user persistent cart, quote/revalidation, idempotent COD orders, inventory transaction, outbox, Kafka retry/DLT, and success navigation.
7. `hardening-accessibility-ci`: OWASP hardening, complete localization/accessibility/snapshots, E2E journeys, SonarQube, dependency/security scanning, coverage gates, and unsigned iOS build.

---

### Task 1: Toolchain and Secret Boundary

**Files:**
- Create: `.mise.toml`
- Create: `.env.example`
- Create: `Makefile`
- Create: `Infrastructure/scripts/check-tools.sh`
- Create: `Infrastructure/tests/check-tools_test.sh`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: a POSIX-like shell on macOS and Docker Desktop with Compose v2.
- Produces: `make bootstrap`, `make test-foundation`, and environment keys `COMMERCE_HOST`, `POSTGRES_*`, `REDIS_PASSWORD`, `KAFKA_IMAGE`, and `CADDY_IMAGE` used by later tasks.

- [ ] **Step 1: Write the failing preflight test**

Create `Infrastructure/tests/check-tools_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fake_bin="$(mktemp -d)"
trap 'rm -rf "$fake_bin"' EXIT

for tool in go docker mkcert make python3; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin/$tool"
  chmod +x "$fake_bin/$tool"
done

output="$(PATH="$fake_bin:/usr/bin:/bin" "$root/Infrastructure/scripts/check-tools.sh")"
[[ "$output" == *"foundation tools available"* ]]

rm "$fake_bin/mkcert"
if PATH="$fake_bin:/usr/bin:/bin" "$root/Infrastructure/scripts/check-tools.sh" 2>"$fake_bin/error"; then
  echo "expected missing mkcert to fail" >&2
  exit 1
fi
grep -q "missing required tool: mkcert" "$fake_bin/error"
```

- [ ] **Step 2: Run the test and verify the script is missing**

Run: `bash Infrastructure/tests/check-tools_test.sh`

Expected: FAIL with `Infrastructure/scripts/check-tools.sh: No such file or directory`.

- [ ] **Step 3: Add the version contract, defaults, Make targets, and preflight**

Create `.mise.toml`:

```toml
[tools]
go = "1.26.5"
```

Create `.env.example`:

```dotenv
COMMERCE_HOST=commerce.local
HTTPS_PORT=8443
POSTGRES_DB=commerce
POSTGRES_USER=commerce
POSTGRES_PASSWORD=local-postgres-change-me
REDIS_PASSWORD=local-redis-change-me
POSTGRES_IMAGE=postgres:18.4-alpine
REDIS_IMAGE=redis:8.2-alpine
KAFKA_IMAGE=apache/kafka:4.3.1
CADDY_IMAGE=caddy:2.10.0-alpine
API_IMAGE=commerce-api:local
```

Create `Infrastructure/scripts/check-tools.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

for tool in go docker mkcert make python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing required tool: $tool" >&2
    exit 1
  fi
done

docker compose version >/dev/null
echo "foundation tools available"
```

Create `Makefile`:

```make
SHELL := /bin/bash
COMPOSE := docker compose --env-file .env -f Infrastructure/compose.yaml

.PHONY: bootstrap certs infra-up infra-down infra-logs test-go test-foundation smoke

bootstrap:
	@Infrastructure/scripts/check-tools.sh

certs:
	@Infrastructure/scripts/create-certs.sh

infra-up:
	@$(COMPOSE) up --build --wait

infra-down:
	@$(COMPOSE) down --remove-orphans

infra-logs:
	@$(COMPOSE) logs -f --tail=200

test-go:
	@cd Backend && go test -race ./...

test-foundation:
	@bash Infrastructure/tests/check-tools_test.sh
	@bash Infrastructure/tests/compose_test.sh
	@bash Infrastructure/tests/certs_test.sh
	@bash Infrastructure/tests/smoke_test.sh

smoke:
	@Infrastructure/scripts/smoke.sh
```

Append these exact entries to `.gitignore`:

```gitignore
# Local infrastructure
.env
Infrastructure/certs/*
!Infrastructure/certs/.gitkeep
Infrastructure/data/
```

Run: `chmod +x Infrastructure/scripts/check-tools.sh Infrastructure/tests/check-tools_test.sh`

- [ ] **Step 4: Run the preflight test**

Run: `bash Infrastructure/tests/check-tools_test.sh`

Expected: PASS with no output after its assertions.

- [ ] **Step 5: Verify ignored secrets and commit**

Run: `touch .env Infrastructure-private.key && git check-ignore .env && rm Infrastructure-private.key`

Expected: `.env` is printed. Then run:

```bash
git add .mise.toml .env.example .gitignore Makefile Infrastructure/scripts/check-tools.sh Infrastructure/tests/check-tools_test.sh
git commit -m "chore: define foundation toolchain"
```

### Task 2: Go Liveness API

**Files:**
- Create: `Backend/go.mod`
- Create: `Backend/internal/health/handler.go`
- Create: `Backend/internal/health/handler_test.go`
- Create: `Backend/cmd/api/main.go`

**Interfaces:**
- Consumes: `PORT`, defaulting to `8080`.
- Produces: `health.NewHandler() http.Handler`, `GET /healthz`, JSON `{"status":"ok"}`, HTTP 200, and graceful SIGINT/SIGTERM shutdown.

- [ ] **Step 1: Write the failing handler tests**

Create `Backend/go.mod`:

```go
module github.com/vominhtri1049/learning-superpower/backend

go 1.26.5
```

Create `Backend/internal/health/handler_test.go`:

```go
package health_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/vominhtri1049/learning-superpower/backend/internal/health"
)

func TestHandlerReturnsLiveness(t *testing.T) {
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)

	health.NewHandler().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}
	if got, want := recorder.Header().Get("Content-Type"), "application/json"; got != want {
		t.Fatalf("content type = %q, want %q", got, want)
	}
	if got, want := recorder.Body.String(), "{\"status\":\"ok\"}\n"; got != want {
		t.Fatalf("body = %q, want %q", got, want)
	}
}

func TestHandlerRejectsNonGET(t *testing.T) {
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/healthz", nil)

	health.NewHandler().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusMethodNotAllowed)
	}
}
```

- [ ] **Step 2: Run the focused tests to verify failure**

Run: `cd Backend && go test ./internal/health -v`

Expected: FAIL because package `internal/health` has no non-test Go files and `NewHandler` is undefined.

- [ ] **Step 3: Implement the handler**

Create `Backend/internal/health/handler.go`:

```go
package health

import "net/http"

func NewHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("{\"status\":\"ok\"}\n"))
	})
}
```

- [ ] **Step 4: Run tests and add the process entry point**

Run: `cd Backend && go test -race ./internal/health -v`

Expected: PASS for both tests with no race report.

Create `Backend/cmd/api/main.go`:

```go
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/vominhtri1049/learning-superpower/backend/internal/health"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.Handle("/healthz", health.NewHandler())
	server := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			slog.Error("server shutdown failed", "error", err)
		}
	}()

	slog.Info("api listening", "port", port)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		slog.Error("api stopped unexpectedly", "error", err)
		os.Exit(1)
	}
}
```

- [ ] **Step 5: Verify the entire Go module and commit**

Run: `cd Backend && gofmt -w cmd/api/main.go internal/health/*.go && go vet ./... && go test -race ./...`

Expected: all commands exit 0 and both health tests pass.

```bash
git add Backend
git commit -m "feat: add backend liveness endpoint"
```

### Task 3: Reproducible API Container

**Files:**
- Create: `Backend/Dockerfile`
- Create: `Backend/.dockerignore`

**Interfaces:**
- Consumes: the Go API from Task 2.
- Produces: `commerce-api:local`, running as numeric non-root user `10001`, listening on port 8080.

- [ ] **Step 1: Demonstrate the image is absent**

Run: `docker image inspect commerce-api:local`

Expected: FAIL with `No such image: commerce-api:local`.

- [ ] **Step 2: Add the multi-stage image definition**

Create `Backend/Dockerfile`:

```dockerfile
FROM golang:1.26.5-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/api /api
EXPOSE 8080
USER 10001:10001
ENTRYPOINT ["/api"]
```

Create `Backend/.dockerignore`:

```dockerignore
.git
.build
coverage.out
```

- [ ] **Step 3: Build and inspect the non-root image**

Run: `docker build -t commerce-api:local Backend`

Expected: image build completes. Then run:

```bash
test "$(docker image inspect commerce-api:local --format '{{.Config.User}}')" = "10001:10001"
```

Expected: exit 0.

- [ ] **Step 4: Exercise the container directly**

Run:

```bash
container_id="$(docker run -d -p 18080:8080 commerce-api:local)"
trap 'docker rm -f "$container_id" >/dev/null' EXIT
for _ in {1..20}; do curl -fsS http://127.0.0.1:18080/healthz && break; sleep 0.25; done
```

Expected: `{"status":"ok"}`.

- [ ] **Step 5: Commit**

```bash
git add Backend/Dockerfile Backend/.dockerignore
git commit -m "build: containerize backend api"
```

### Task 4: Docker Compose Service Topology

**Files:**
- Create: `Infrastructure/compose.yaml`
- Create: `Infrastructure/tests/compose_test.sh`

**Interfaces:**
- Consumes: exact environment keys from Task 1 and the API image from Task 3.
- Produces: Compose services `postgres`, `redis`, `kafka`, `api`, and `caddy`; only Caddy publishes the application port.

- [ ] **Step 1: Write the failing Compose contract test**

Create `Infrastructure/tests/compose_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
cp .env.example .env
trap 'rm -f .env' EXIT

rendered="$(docker compose --env-file .env -f Infrastructure/compose.yaml config --services)"
for service in postgres redis kafka api caddy; do
  grep -qx "$service" <<<"$rendered"
done

published="$(docker compose --env-file .env -f Infrastructure/compose.yaml config --format json)"
python3 -c 'import json,sys; d=json.load(sys.stdin); assert "ports" not in d["services"]["api"]; assert len(d["services"]["caddy"]["ports"]) == 1' <<<"$published"
```

- [ ] **Step 2: Run it and verify the Compose file is missing**

Run: `bash Infrastructure/tests/compose_test.sh`

Expected: FAIL because `Infrastructure/compose.yaml` does not exist.

- [ ] **Step 3: Add the service topology**

Create `Infrastructure/compose.yaml`:

```yaml
name: learning-superpower

services:
  postgres:
    image: ${POSTGRES_IMAGE}
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 3s
      timeout: 3s
      retries: 20
    networks: [backend]

  redis:
    image: ${REDIS_IMAGE}
    command: ["redis-server", "--appendonly", "yes", "--requirepass", "${REDIS_PASSWORD}"]
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a '$${REDIS_PASSWORD}' ping | grep PONG"]
      interval: 3s
      timeout: 3s
      retries: 20
    environment:
      REDIS_PASSWORD: ${REDIS_PASSWORD}
    networks: [backend]

  kafka:
    image: ${KAFKA_IMAGE}
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_LISTENERS: PLAINTEXT://:9092,CONTROLLER://:9093
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka:9093
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
    healthcheck:
      test: ["CMD-SHELL", "/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 >/dev/null"]
      interval: 5s
      timeout: 5s
      retries: 30
    volumes:
      - kafka-data:/var/lib/kafka/data
    networks: [backend]

  api:
    image: ${API_IMAGE}
    build:
      context: ../Backend
    environment:
      PORT: 8080
      POSTGRES_DSN: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable
      REDIS_ADDR: redis:6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      KAFKA_BROKERS: kafka:9092
    depends_on:
      postgres: {condition: service_healthy}
      redis: {condition: service_healthy}
      kafka: {condition: service_healthy}
    healthcheck:
      test: ["CMD", "/api", "healthcheck"]
      interval: 5s
      timeout: 3s
      retries: 12
    networks: [backend]

  caddy:
    image: ${CADDY_IMAGE}
    ports:
      - "${HTTPS_PORT}:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./certs:/certs:ro
    depends_on:
      api: {condition: service_healthy}
    networks: [backend]

networks:
  backend:
    internal: true

volumes:
  postgres-data:
  redis-data:
  kafka-data:
```

Extend `Backend/cmd/api/main.go` before server setup so the same distroless binary can implement its healthcheck without adding curl:

```go
if len(os.Args) == 2 && os.Args[1] == "healthcheck" {
	response, err := http.Get("http://127.0.0.1:8080/healthz") // #nosec G107 -- fixed loopback health endpoint
	if err != nil || response.StatusCode != http.StatusOK {
		os.Exit(1)
	}
	_ = response.Body.Close()
	return
}
```

- [ ] **Step 4: Validate configuration and Go tests**

Run:

```bash
chmod +x Infrastructure/tests/compose_test.sh
bash Infrastructure/tests/compose_test.sh
cd Backend && gofmt -w cmd/api/main.go && go test -race ./...
```

Expected: Compose contract and Go tests pass.

- [ ] **Step 5: Commit**

```bash
git add Backend/cmd/api/main.go Infrastructure/compose.yaml Infrastructure/tests/compose_test.sh
git commit -m "infra: define local service topology"
```

### Task 5: Local TLS Generation and Caddy Routing

**Files:**
- Create: `Infrastructure/Caddyfile`
- Create: `Infrastructure/certs/.gitkeep`
- Create: `Infrastructure/scripts/create-certs.sh`
- Create: `Infrastructure/tests/certs_test.sh`

**Interfaces:**
- Consumes: `COMMERCE_HOST`, optional `COMMERCE_LAN_IP`, and mkcert.
- Produces: ignored files `Infrastructure/certs/commerce.local.pem` and `commerce.local-key.pem`, plus HTTPS reverse proxying to `api:8080`.

- [ ] **Step 1: Write the failing isolated certificate-script test**

Create `Infrastructure/tests/certs_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/mkcert" <<'MOCK'
#!/usr/bin/env bash
while (($#)); do
  case "$1" in
    -cert-file) cert="$2"; shift 2 ;;
    -key-file) key="$2"; shift 2 ;;
    *) shift ;;
  esac
done
touch "$cert" "$key"
MOCK
chmod +x "$tmp/mkcert"

CERT_DIR="$tmp/certs" COMMERCE_HOST=commerce.local COMMERCE_LAN_IP=192.0.2.10 PATH="$tmp:/usr/bin:/bin" "$root/Infrastructure/scripts/create-certs.sh"
test -f "$tmp/certs/commerce.local.pem"
test -f "$tmp/certs/commerce.local-key.pem"
```

- [ ] **Step 2: Run it and verify the generator is missing**

Run: `bash Infrastructure/tests/certs_test.sh`

Expected: FAIL with `create-certs.sh: No such file or directory`.

- [ ] **Step 3: Implement certificate generation and routing**

Create `Infrastructure/scripts/create-certs.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cert_dir="${CERT_DIR:-$root/Infrastructure/certs}"
host="${COMMERCE_HOST:-commerce.local}"
lan_ip="${COMMERCE_LAN_IP:-}"
mkdir -p "$cert_dir"

names=("$host" localhost 127.0.0.1 ::1)
if [[ -n "$lan_ip" ]]; then names+=("$lan_ip"); fi

mkcert -cert-file "$cert_dir/commerce.local.pem" -key-file "$cert_dir/commerce.local-key.pem" "${names[@]}"
chmod 600 "$cert_dir/commerce.local-key.pem"
echo "certificate created for: ${names[*]}"
echo "local CA: $(mkcert -CAROOT)"
```

Create `Infrastructure/Caddyfile`:

```caddyfile
{$COMMERCE_HOST:commerce.local} {
	tls /certs/commerce.local.pem /certs/commerce.local-key.pem
	encode zstd gzip
	header {
		-Server
		X-Content-Type-Options nosniff
		Referrer-Policy no-referrer
	}
	reverse_proxy api:8080
}
```

Create the empty tracked file `Infrastructure/certs/.gitkeep`.

Replace the `caddy` service with this complete definition in `Infrastructure/compose.yaml`:

```yaml
  caddy:
    image: ${CADDY_IMAGE}
    environment:
      COMMERCE_HOST: ${COMMERCE_HOST}
    ports:
      - "${HTTPS_PORT}:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./certs:/certs:ro
    depends_on:
      api: {condition: service_healthy}
    networks: [backend]
```

- [ ] **Step 4: Run certificate and Compose tests**

Run:

```bash
chmod +x Infrastructure/scripts/create-certs.sh Infrastructure/tests/certs_test.sh
bash Infrastructure/tests/certs_test.sh
bash Infrastructure/tests/compose_test.sh
```

Expected: both scripts exit 0; no generated private key appears in `git status --short`.

- [ ] **Step 5: Commit**

```bash
git add Infrastructure/Caddyfile Infrastructure/certs/.gitkeep Infrastructure/scripts/create-certs.sh Infrastructure/tests/certs_test.sh Infrastructure/compose.yaml
git commit -m "infra: add trusted local tls"
```

### Task 6: End-to-End Infrastructure Smoke Test

**Files:**
- Create: `Infrastructure/scripts/smoke.sh`
- Create: `Infrastructure/tests/smoke_test.sh`

**Interfaces:**
- Consumes: a running Compose project, the mkcert root CA, `COMMERCE_HOST`, and `HTTPS_PORT`.
- Produces: a single `foundation smoke passed` result after HTTPS, PostgreSQL, Redis, and Kafka checks.

- [ ] **Step 1: Write the smoke helper behavior test**

Create `Infrastructure/tests/smoke_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/curl" <<'MOCK'
#!/usr/bin/env bash
printf '{"status":"ok"}\n'
MOCK
cat >"$tmp/docker" <<'MOCK'
#!/usr/bin/env bash
if [[ " $* " == *" redis "* ]]; then
  printf 'PONG\n'
fi
exit 0
MOCK
cat >"$tmp/mkcert" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_CA_ROOT:?}"
MOCK
chmod +x "$tmp/curl" "$tmp/docker" "$tmp/mkcert"
touch "$tmp/rootCA.pem"

output="$(FAKE_CA_ROOT="$tmp" PATH="$tmp:/usr/bin:/bin" COMMERCE_HOST=commerce.local HTTPS_PORT=8443 "$root/Infrastructure/scripts/smoke.sh")"
[[ "$output" == *"foundation smoke passed"* ]]
```

- [ ] **Step 2: Run it and verify the smoke script is missing**

Run: `bash Infrastructure/tests/smoke_test.sh`

Expected: FAIL because `Infrastructure/scripts/smoke.sh` does not exist.

- [ ] **Step 3: Implement all dependency checks**

Create `Infrastructure/scripts/smoke.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
host="${COMMERCE_HOST:-commerce.local}"
port="${HTTPS_PORT:-8443}"
ca_file="$(mkcert -CAROOT)/rootCA.pem"

curl --fail --silent --show-error --cacert "$ca_file" --resolve "$host:$port:127.0.0.1" "https://$host:$port/healthz" | grep -qx '{"status":"ok"}'
docker compose --env-file .env -f Infrastructure/compose.yaml exec -T postgres pg_isready -U "${POSTGRES_USER:-commerce}" -d "${POSTGRES_DB:-commerce}" >/dev/null
docker compose --env-file .env -f Infrastructure/compose.yaml exec -T redis redis-cli -a "${REDIS_PASSWORD:-local-redis-change-me}" ping 2>/dev/null | grep -qx PONG
docker compose --env-file .env -f Infrastructure/compose.yaml exec -T kafka /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 >/dev/null
echo "foundation smoke passed"
```

- [ ] **Step 4: Run isolated tests, then the real local stack**

Run:

```bash
chmod +x Infrastructure/scripts/smoke.sh Infrastructure/tests/smoke_test.sh
bash Infrastructure/tests/smoke_test.sh
cp -n .env.example .env
make certs
make infra-up
make smoke
```

Expected: all Compose services become healthy and the final line is `foundation smoke passed`.

- [ ] **Step 5: Tear down and commit**

Run: `make infra-down`

Expected: containers and the project network are removed; named data volumes remain.

```bash
git add Infrastructure/scripts/smoke.sh Infrastructure/tests/smoke_test.sh
git commit -m "test: verify local infrastructure smoke flow"
```

### Task 7: Foundation CI and Local Setup Documentation

**Files:**
- Create: `.github/workflows/foundation.yml`
- Create: `docs/development/local-setup.md`

**Interfaces:**
- Consumes: Tasks 1-6 and GitHub-hosted Ubuntu runners.
- Produces: required-quality candidate jobs `go` and `infrastructure`; exact developer trust/start/stop instructions.

- [ ] **Step 1: Add the CI workflow**

Create `.github/workflows/foundation.yml`:

```yaml
name: Foundation

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: foundation-${{ github.ref }}
  cancel-in-progress: true

jobs:
  go:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: 1.26.5
          cache: false
      - run: gofmt -w cmd internal && git diff --exit-code
        working-directory: Backend
      - run: go vet ./...
        working-directory: Backend
      - run: go test -race -coverprofile=coverage.out ./...
        working-directory: Backend
      - uses: actions/upload-artifact@v4
        with:
          name: go-coverage
          path: Backend/coverage.out

  infrastructure:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install mkcert
        run: |
          sudo apt-get update
          sudo apt-get install -y mkcert libnss3-tools
      - run: cp .env.example .env
      - run: bash Infrastructure/tests/check-tools_test.sh
      - run: bash Infrastructure/tests/compose_test.sh
      - run: bash Infrastructure/tests/certs_test.sh
      - run: bash Infrastructure/tests/smoke_test.sh
      - run: make certs
      - run: make infra-up
      - run: make smoke
      - if: always()
        run: docker compose --env-file .env -f Infrastructure/compose.yaml logs --no-color > foundation.log
      - if: always()
        uses: actions/upload-artifact@v4
        with:
          name: foundation-logs
          path: foundation.log
      - if: always()
        run: make infra-down
```

- [ ] **Step 2: Add exact local setup instructions**

Create `docs/development/local-setup.md`:

```markdown
# Local Foundation Setup

## Prerequisites

Install Docker Desktop, mise, mkcert, and Make. Run `mise install`, then verify with `make bootstrap`.

## Configure and start

1. Copy `.env.example` to `.env` and replace both local passwords.
2. Set `COMMERCE_HOST=commerce.local`. For a physical iPhone, also export `COMMERCE_LAN_IP` with the Mac's LAN address before generating certificates.
3. Run `mkcert -install`, `make certs`, `make infra-up`, and `make smoke`.
4. Stop services with `make infra-down`; inspect failures with `make infra-logs`.

## Trust on iOS Simulator

Drag the file printed by `mkcert -CAROOT` named `rootCA.pem` onto the booted Simulator. In Settings, enable full trust under General > About > Certificate Trust Settings.

## Trust on a physical iPhone

Transfer only `rootCA.pem` to the device, install the profile, then enable full trust under Settings > General > About > Certificate Trust Settings. Never transfer `commerce.local-key.pem` to a device.

## Verify HTTPS

Run `make smoke`. The expected final line is `foundation smoke passed`. A TLS trust failure must fail closed; do not use curl `-k` or disable ATS in later app work.
```

- [ ] **Step 3: Validate workflow syntax and all fast checks**

Run:

```bash
cp -n .env.example .env
docker compose --env-file .env -f Infrastructure/compose.yaml config --quiet
cd Backend && gofmt -w cmd internal && go vet ./... && go test -race ./...
cd .. && make test-foundation
git diff --check
```

Expected: every command exits 0; `git diff --check` prints nothing.

- [ ] **Step 4: Run the real final smoke check**

Run:

```bash
make certs
make infra-up
make smoke
make infra-down
```

Expected: `foundation smoke passed`, followed by clean Compose shutdown.

- [ ] **Step 5: Commit the CI and documentation**

```bash
git add .github/workflows/foundation.yml docs/development/local-setup.md
git commit -m "ci: verify foundation and local infrastructure"
```

## Plan 1 Completion Gate

Before starting plan 2, run:

```bash
git status --short
make bootstrap
make test-go
make test-foundation
make certs
make infra-up
make smoke
make infra-down
```

Expected results:

- Git status contains no unintended generated certificate, key, password, or environment file.
- All unit and shell contract tests pass.
- PostgreSQL, Redis, Kafka, the Go API, and Caddy become healthy.
- The trusted HTTPS endpoint returns exactly `{"status":"ok"}`.
- The API container runs as user `10001:10001`.
- No service except Caddy publishes a host port.

The next plan may consume only the stable outputs declared here: repository paths, Make targets, environment names, Compose service names, and the HTTPS `/healthz` contract.
