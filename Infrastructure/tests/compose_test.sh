#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
compose=(docker compose --env-file "$root/.env.example" -f "$root/Infrastructure/compose.yaml")

services="$(${compose[@]} config --services)"
for service in postgres redis kafka api caddy; do
  grep -qx "$service" <<<"$services"
done

${compose[@]} config --format json | python3 -c '
import json
import sys

config = json.load(sys.stdin)
services = config["services"]
assert "ports" not in services["api"]
assert len(services["caddy"]["ports"]) == 1
assert config["networks"]["backend"]["internal"] is True
assert config["networks"]["edge"].get("internal", False) is False
assert set(services["caddy"]["networks"]) == {"backend", "edge"}
assert all("edge" not in service.get("networks", {}) for name, service in services.items() if name != "caddy")
redis_healthcheck = services["redis"]["healthcheck"]["test"][-1]
assert "-a $${REDIS_PASSWORD}" in redis_healthcheck, redis_healthcheck
'
