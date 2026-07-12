#!/usr/bin/env bash
set -euo pipefail

for tool in go docker mkcert make python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing required tool: $tool" >&2
    exit 1
  fi
done

if ! docker compose version >/dev/null 2>&1; then
  echo "missing required tool: docker compose" >&2
  exit 1
fi

echo "foundation tools available"
