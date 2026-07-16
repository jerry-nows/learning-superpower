package main

import (
	"context"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
)

func TestCatalogSeedContainsDeterministicFixtures(t *testing.T) {
	if len(seedCategories) != 3 || len(seedProducts) != 6 {
		t.Fatalf("fixture sizes = categories:%d products:%d", len(seedCategories), len(seedProducts))
	}
	seenCategories := make(map[string]bool)
	for _, category := range seedCategories {
		if category.id == "" || category.name == "" || category.slug == "" || seenCategories[category.id] {
			t.Fatalf("invalid or duplicate category: %#v", category)
		}
		seenCategories[category.id] = true
	}
	seenProducts := make(map[string]bool)
	for _, product := range seedProducts {
		if product.id == "" || product.categoryID == "" || product.name == "" || product.price < 0 || product.stock < 0 || seenProducts[product.id] {
			t.Fatalf("invalid or duplicate product: %#v", product)
		}
		if !seenCategories[product.categoryID] {
			t.Fatalf("product references unknown category: %#v", product)
		}
		seenProducts[product.id] = true
	}
}

func TestCatalogSeedIsIdempotentAndDoesNotLogSecrets(t *testing.T) {
	db := &catalogSeedDB{}
	if err := seedCatalog(context.Background(), db); err != nil {
		t.Fatalf("first seed: %v", err)
	}
	first := append([]string(nil), db.queries...)
	if err := seedCatalog(context.Background(), db); err != nil {
		t.Fatalf("second seed: %v", err)
	}
	if len(db.queries) != 2*len(first) || strings.Join(first, "\n") != strings.Join(db.queries[len(first):], "\n") {
		t.Fatal("catalog seed is not deterministic across runs")
	}
	for _, query := range first {
		if !strings.Contains(query, "ON CONFLICT") {
			t.Fatalf("seed query is not idempotent: %s", query)
		}
	}
	if strings.Contains(strings.Join(first, "\n"), "password") || strings.Contains(strings.Join(first, "\n"), "DATABASE_URL") {
		t.Fatal("catalog SQL contains credential material")
	}
}

type catalogSeedDB struct{ queries []string }

func (db *catalogSeedDB) Ping(context.Context) error { return nil }
func (db *catalogSeedDB) Exec(_ context.Context, query string, _ ...any) (pgconn.CommandTag, error) {
	db.queries = append(db.queries, query)
	return pgconn.CommandTag{}, nil
}
func (db *catalogSeedDB) Close() {}
