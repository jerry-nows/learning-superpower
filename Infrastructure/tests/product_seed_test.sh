#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
seed="$root/Backend/cmd/seed/main.go"
test_file="$root/Backend/cmd/seed/product_seed_test.go"

[[ -f "$seed" ]] || { echo "seed command is missing" >&2; exit 1; }
[[ -f "$test_file" ]] || { echo "product seed tests are missing" >&2; exit 1; }
grep -Fq 'seedCategories' "$seed"
grep -Fq 'seedProducts' "$seed"
grep -Fq 'upsertCategorySQL' "$seed"
grep -Fq 'upsertProductSQL' "$seed"
grep -Fq 'ON CONFLICT (id)' "$seed"
grep -Fq 'seedCatalog(ctx, db)' "$seed"
grep -Fq 'TestCatalogSeedIsIdempotentAndDoesNotLogSecrets' "$test_file"

echo 'PASS: deterministic product seed contract'
