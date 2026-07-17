package migrations_test

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

func TestProductMigrationDefinesCatalogTablesAndRollback(t *testing.T) {
	t.Parallel()

	contents, err := os.ReadFile("000002_product.sql")
	if err != nil {
		t.Fatalf("read product migration: %v", err)
	}

	sql := strings.ToLower(string(contents))
	patterns := map[string]string{
		"goose up section":             `--\s*\+goose\s+up`,
		"goose down section":           `--\s*\+goose\s+down`,
		"categories table":             `create\s+table\s+categories`,
		"products table":               `create\s+table\s+products`,
		"category generated UUID":      `categories[\s\S]*?id\s+uuid\s+primary\s+key\s+default\s+gen_random_uuid\(\)`,
		"product generated UUID":       `products[\s\S]*?id\s+uuid\s+primary\s+key\s+default\s+gen_random_uuid\(\)`,
		"product category foreign key": `category_id\s+uuid[\s\S]*?references\s+categories\s*\(\s*id\s*\)`,
		"product price":                `price\s+(?:bigint|numeric|decimal)\s+not\s+null`,
		"product stock":                `stock\s+integer\s+not\s+null`,
		"product status":               `status\s+text\s+not\s+null\s+default\s+'active'`,
		"product created timestamp":    `created_at\s+timestamptz\s+not\s+null\s+default\s+now\(\)`,
		"product updated timestamp":    `updated_at\s+timestamptz\s+not\s+null\s+default\s+now\(\)`,
		"category index":               `create\s+index\s+products_category_idx\s+on\s+products`,
		"status index":                 `create\s+index\s+products_status_idx\s+on\s+products`,
		"products rollback":            `drop\s+table\s+if\s+exists\s+products`,
		"categories rollback":          `drop\s+table\s+if\s+exists\s+categories`,
	}

	for name, pattern := range patterns {
		if !regexp.MustCompile(pattern).MatchString(sql) {
			t.Errorf("migration is missing %s", name)
		}
	}

	if !strings.Contains(sql, "on delete restrict") {
		t.Error("product category foreign key must restrict category deletion")
	}
}
