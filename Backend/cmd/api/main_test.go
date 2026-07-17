package main

import (
	"context"
	"database/sql"
	"io/fs"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

func TestParseAPIConfigRequiresSecretsAndUsesSafeDefaults(t *testing.T) {
	env := map[string]string{"DATABASE_URL": "postgres://db", "REDIS_URL": "redis://localhost", "JWT_SIGNING_KEY": "01234567890123456789012345678901", "JWT_ISSUER": "local", "JWT_AUDIENCE": "ios"}
	c, err := parseAPIConfig(func(k string) string { return env[k] })
	if err != nil {
		t.Fatalf("parse config: %v", err)
	}
	if c.port != "8080" || c.migrationsDir != "migrations" {
		t.Fatalf("unsafe defaults: %#v", c)
	}
}

func TestBuildApplicationRejectsMissingMigrationDirectoryBeforeOpeners(t *testing.T) {
	opened := false
	deps := startupDependencies{openSQL: func(context.Context, string) (*sql.DB, error) { opened = true; return nil, nil }, openPool: func(context.Context, string) (*pgxpool.Pool, error) { return nil, nil }, newRedis: func(string) (*redis.Client, error) { return nil, nil }, runMigrations: func(context.Context, *sql.DB, fs.FS) error { return nil }}
	cfg := apiConfig{databaseURL: "db", redisURL: "redis://localhost", jwtSigningKey: strings.Repeat("k", 32), jwtIssuer: "issuer", jwtAudience: "aud", migrationsDir: t.TempDir() + "/missing"}
	if _, err := buildApplication(context.Background(), cfg, deps); err == nil {
		t.Fatal("expected missing migration directory error")
	}
	if opened {
		t.Fatal("database opener called before migration directory validation")
	}
}

func TestBuildApplicationClosesSQLWhenStartupFails(t *testing.T) {
	dir := t.TempDir()
	closed := 0
	deps := productionDependencies()
	deps.openSQL = func(context.Context, string) (*sql.DB, error) { return sql.Open("pgx", "postgres://127.0.0.1:1/db") }
	deps.closeSQL = func(db *sql.DB) { closed++; _ = db.Close() }
	cfg := apiConfig{databaseURL: "db", redisURL: "redis://localhost", jwtSigningKey: strings.Repeat("k", 32), jwtIssuer: "issuer", jwtAudience: "aud", migrationsDir: dir}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if _, err := buildApplication(ctx, cfg, deps); err == nil {
		t.Fatal("expected startup failure")
	}
	if closed != 1 {
		t.Fatalf("sql close count = %d, want 1", closed)
	}
}

func TestParseAPIConfigRejectsShortSigningKey(t *testing.T) {
	env := map[string]string{"DATABASE_URL": "postgres://db", "REDIS_URL": "redis://localhost", "JWT_SIGNING_KEY": "short", "JWT_ISSUER": "local", "JWT_AUDIENCE": "ios"}
	if _, err := parseAPIConfig(func(k string) string { return env[k] }); err == nil {
		t.Fatal("expected short JWT signing key to be rejected")
	}
}

func TestParseAPIConfigDoesNotExposeValuesInError(t *testing.T) {
	env := map[string]string{"DATABASE_URL": "postgres://dsn-secret", "JWT_SIGNING_KEY": "short", "JWT_ISSUER": "issuer-secret", "JWT_AUDIENCE": "audience-secret"}
	_, err := parseAPIConfig(func(k string) string { return env[k] })
	if err == nil {
		t.Fatal("expected invalid config")
	}
	for _, secret := range []string{"dsn-secret", "issuer-secret", "audience-secret"} {
		if strings.Contains(err.Error(), secret) {
			t.Fatalf("error leaked %q", secret)
		}
	}
}
