#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
compose=(docker compose --env-file "$root/.env.example" -f "$root/Infrastructure/compose.yaml")

services="$(${compose[@]} config --services)"
for service in postgres redis kafka api seed caddy; do
  grep -qx "$service" <<<"$services"
done

${compose[@]} config --format json | python3 -c '
import json
import sys

config = json.load(sys.stdin)
services = config["services"]
assert "ports" not in services["api"]
assert "ports" not in services["seed"]
assert len(services["caddy"]["ports"]) == 1
assert config["networks"]["backend"]["internal"] is True
assert config["networks"]["edge"].get("internal", False) is False
assert set(services["caddy"]["networks"]) == {"backend", "edge"}
assert all("edge" not in service.get("networks", {}) for name, service in services.items() if name != "caddy")
redis_healthcheck = services["redis"]["healthcheck"]["test"][-1]
assert "-a $${REDIS_PASSWORD}" in redis_healthcheck, redis_healthcheck
api_env = services["api"]["environment"]
for key in ("DATABASE_URL", "REDIS_URL", "JWT_SIGNING_KEY", "JWT_ISSUER", "JWT_AUDIENCE", "MIGRATIONS_DIR"):
    assert key in api_env, key
assert api_env["MIGRATIONS_DIR"] == "/migrations"
assert "POSTGRES_DSN" not in api_env
seed = services["seed"]
assert seed["entrypoint"] == ["/seed"]
assert seed["depends_on"]["api"]["condition"] == "service_started"
for key in ("DATABASE_URL", "SEED_USER_EMAIL", "SEED_USER_PASSWORD"):
    assert key in seed["environment"], key
assert set(services["seed"]["networks"]) == {"backend"}
'
