package migrations_test

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

func TestReviewsMigrationDefinesReviewAndCommentPersistence(t *testing.T) {
	t.Parallel()

	contents, err := os.ReadFile("000003_reviews.sql")
	if err != nil {
		t.Fatalf("read reviews migration: %v", err)
	}

	sql := strings.ToLower(string(contents))
	patterns := map[string]string{
		"goose up section":          `--\s*\+goose\s+up`,
		"goose down section":        `--\s*\+goose\s+down`,
		"reviews table":              `create\s+table\s+reviews`,
		"comments table":             `create\s+table\s+comments`,
		"review product foreign key": `reviews[\s\S]*?product_id\s+uuid[\s\S]*?references\s+products\s*\(\s*id\s*\)`,
		"comment product foreign key": `comments[\s\S]*?product_id\s+uuid[\s\S]*?references\s+products\s*\(\s*id\s*\)`,
		"review rating constraint":   `reviews[\s\S]*?rating\s+between\s+1\s+and\s+5`,
		"review product index":        `create\s+index\s+reviews_product_created_idx\s+on\s+reviews`,
		"comment product index":       `create\s+index\s+comments_product_created_idx\s+on\s+comments`,
		"reviews rollback":            `drop\s+table\s+if\s+exists\s+reviews`,
		"comments rollback":           `drop\s+table\s+if\s+exists\s+comments`,
	}

	for name, pattern := range patterns {
		if !regexp.MustCompile(pattern).MatchString(sql) {
			t.Errorf("migration is missing %s", name)
		}
	}

	if !strings.Contains(sql, "on delete cascade") {
		t.Error("review and comment product foreign keys must cascade when a product is deleted")
	}
}
