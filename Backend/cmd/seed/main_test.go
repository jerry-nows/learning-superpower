package main

import (
	"context"
	"errors"
	"github.com/jackc/pgx/v5/pgconn"
	"strings"
	"testing"
)

type fakeSeedDB struct {
	pingErr error
	execErr error
	query   string
	args    []any
	closed  bool
}

func (f *fakeSeedDB) Ping(context.Context) error { return f.pingErr }
func (f *fakeSeedDB) Exec(_ context.Context, query string, args ...any) (pgconn.CommandTag, error) {
	f.query, f.args = query, args
	return pgconn.CommandTag{}, f.execErr
}
func (f *fakeSeedDB) Close() { f.closed = true }

type fakeSeedHasher struct {
	hash     string
	err      error
	password string
}

func (f *fakeSeedHasher) Hash(password string) (string, error) {
	f.password = password
	return f.hash, f.err
}

func TestSeedRequiresEnvironmentWithoutLeakingValues(t *testing.T) {
	secret := "SuperSecret123!"
	errOutput := new(strings.Builder)
	err := run(context.Background(), func(string) string { return "" }, nil, errOutput, nil, nil)
	if err == nil || !strings.Contains(err.Error(), "required") {
		t.Fatalf("error = %v", err)
	}
	if strings.Contains(errOutput.String(), secret) {
		t.Fatal("secret leaked")
	}
}

func TestSeedNormalizesAndUpsertsWithoutPII(t *testing.T) {
	db := &fakeSeedDB{}
	hasher := &fakeSeedHasher{hash: "$argon2id$hash"}
	env := map[string]string{"DATABASE_URL": "postgres://dsn-secret", "SEED_USER_EMAIL": " User@Example.COM ", "SEED_USER_PASSWORD": "SuperSecret123!"}
	errOutput := new(strings.Builder)
	err := run(context.Background(), func(k string) string { return env[k] }, nil, errOutput, func(context.Context, string) (seedDB, error) { return db, nil }, hasher)
	if err != nil {
		t.Fatalf("run: %v", err)
	}
	if db.closed == false {
		t.Fatal("database was not closed")
	}
	if !strings.Contains(db.query, "ON CONFLICT") || !strings.Contains(db.query, "status") {
		t.Fatalf("query is not idempotent upsert: %s", db.query)
	}
	if got := db.args[0]; got != "user@example.com" {
		t.Fatalf("email arg = %v", got)
	}
	if hasher.password != env["SEED_USER_PASSWORD"] {
		t.Fatal("password was not sent to production hasher")
	}
	if strings.Contains(errOutput.String(), "user@example.com") || strings.Contains(errOutput.String(), secretValue(env)) {
		t.Fatalf("PII leaked: %s", errOutput.String())
	}
}

func TestSeedFailsClosedOnHashOrPingFailure(t *testing.T) {
	db := &fakeSeedDB{pingErr: errors.New("dial secret")}
	env := map[string]string{"DATABASE_URL": "dsn", "SEED_USER_EMAIL": "user@example.com", "SEED_USER_PASSWORD": "SuperSecret123!"}
	err := run(context.Background(), func(k string) string { return env[k] }, nil, new(strings.Builder), func(context.Context, string) (seedDB, error) { return db, nil }, &fakeSeedHasher{hash: "hash", err: errors.New("hash failure")})
	if err == nil {
		t.Fatal("expected ping failure")
	}
	if !db.closed {
		t.Fatal("database was not closed")
	}
}

func secretValue(env map[string]string) string { return env["SEED_USER_PASSWORD"] }
