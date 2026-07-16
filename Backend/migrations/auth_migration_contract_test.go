package migrations_test

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

func TestAuthMigrationDefinesOnlyPostgreSQLUserPersistence(t *testing.T) {
	t.Parallel()

	contents, err := os.ReadFile("000001_auth.sql")
	if err != nil {
		t.Fatalf("read auth migration: %v", err)
	}

	sql := strings.ToLower(string(contents))
	patterns := map[string]string{
		"goose up section":       `--\s*\+goose\s+up`,
		"goose down section":     `--\s*\+goose\s+down`,
		"users table":            `create\s+table\s+users`,
		"generated UUID id":      `id\s+uuid\s+primary\s+key\s+default\s+gen_random_uuid\(\)`,
		"normalized email":       `check\s*\(\s*email\s*=\s*lower\(btrim\(email\)\)\s*\)`,
		"unique email index":     `create\s+unique\s+index\s+users_email_unique_idx\s+on\s+users\s*\(email\)`,
		"internal password hash": `password_hash\s+text\s+not\s+null`,
		"auth status":            `status\s+text\s+not\s+null\s+default\s+'active'`,
		"created timestamp":      `created_at\s+timestamptz\s+not\s+null\s+default\s+now\(\)`,
		"updated timestamp":      `updated_at\s+timestamptz\s+not\s+null\s+default\s+now\(\)`,
		"users rollback":         `drop\s+table\s+if\s+exists\s+users`,
	}

	for name, pattern := range patterns {
		if !regexp.MustCompile(pattern).MatchString(sql) {
			t.Errorf("migration is missing %s", name)
		}
	}

	for _, forbidden := range []string{"refresh_token", "refresh_session", "token_family", "family_id"} {
		if strings.Contains(sql, forbidden) {
			t.Errorf("migration persists %q in PostgreSQL; refresh state belongs exclusively in Redis", forbidden)
		}
	}
}
