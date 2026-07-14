package main

import (
	"context"
	"database/sql"
	"errors"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"io/fs"
	"os"
	"strings"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/testcontainers/testcontainers-go"
	postgrescontainer "github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/vominhtri1049/learning-superpower/backend/internal/auth"
	"github.com/vominhtri1049/learning-superpower/backend/internal/platform/migration"
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
	out := new(strings.Builder)
	err := run(context.Background(), func(k string) string { return env[k] }, nil, out, func(context.Context, string) (seedDB, error) { return db, nil }, &fakeSeedHasher{hash: "hash-secret", err: errors.New("hash failure")})
	if err == nil {
		t.Fatal("expected ping failure")
	}
	if !db.closed {
		t.Fatal("database was not closed")
	}
	assertSeedSecretsRedacted(t, out.String(), err.Error(), "dsn", "user@example.com", "SuperSecret123!", "hash-secret")
}

func TestSeedHashFailureDoesNotExecute(t *testing.T) {
	db := &fakeSeedDB{}
	env := map[string]string{"DATABASE_URL": "dsn", "SEED_USER_EMAIL": "user@example.com", "SEED_USER_PASSWORD": "SuperSecret123!"}
	out := new(strings.Builder)
	err := run(context.Background(), func(k string) string { return env[k] }, nil, out, func(context.Context, string) (seedDB, error) { return db, nil }, &fakeSeedHasher{hash: "hash-secret", err: errors.New("hash failure")})
	if err == nil || db.query != "" {
		t.Fatalf("hash failure = %v, query=%q", err, db.query)
	}
	assertSeedSecretsRedacted(t, out.String(), err.Error(), "dsn", "user@example.com", "SuperSecret123!", "hash-secret")
}

func assertSeedSecretsRedacted(t *testing.T, output, returnedError string, secrets ...string) {
	t.Helper()
	for _, secret := range secrets {
		if strings.Contains(output, secret) || strings.Contains(returnedError, secret) {
			t.Fatalf("secret %q leaked in output/error: %q / %q", secret, output, returnedError)
		}
	}
}

func TestSeedPingSuccessHashFailureDoesNotExecute(t *testing.T) {
	db := &fakeSeedDB{}
	env := map[string]string{"DATABASE_URL": "dsn", "SEED_USER_EMAIL": "user@example.com", "SEED_USER_PASSWORD": "SuperSecret123!"}
	err := run(context.Background(), func(k string) string { return env[k] }, nil, new(strings.Builder), func(context.Context, string) (seedDB, error) { return db, nil }, &fakeSeedHasher{err: errors.New("hash failure")})
	if err == nil || db.query != "" {
		t.Fatalf("hash failure = %v, query=%q", err, db.query)
	}
}

func TestSeedRejectsMissingOrInvalidEnvironmentIndividually(t *testing.T) {
	base := map[string]string{"DATABASE_URL": "dsn", "SEED_USER_EMAIL": "user@example.com", "SEED_USER_PASSWORD": "SuperSecret123!"}
	for _, tc := range []struct{ name, key, value string }{
		{"missing database URL", "DATABASE_URL", ""}, {"missing email", "SEED_USER_EMAIL", ""}, {"invalid email", "SEED_USER_EMAIL", "not-an-email"},
		{"missing password", "SEED_USER_PASSWORD", ""}, {"weak password", "SEED_USER_PASSWORD", "short"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			env := map[string]string{}
			for k, v := range base {
				env[k] = v
			}
			env[tc.key] = tc.value
			out := new(strings.Builder)
			if err := run(context.Background(), func(k string) string { return env[k] }, nil, out, nil, nil); err == nil {
				t.Fatal("expected validation failure")
			}
			if strings.Contains(out.String(), tc.value) && tc.value != "" {
				t.Fatalf("value leaked: %q", out.String())
			}
		})
	}
}

func TestSeedOpenAndExecFailuresAreGeneric(t *testing.T) {
	env := map[string]string{"DATABASE_URL": "postgres://dsn-secret", "SEED_USER_EMAIL": "user@example.com", "SEED_USER_PASSWORD": "SuperSecret123!"}
	for _, tc := range []struct {
		name string
		open seedDBFactory
		db   *fakeSeedDB
	}{
		{"open", func(context.Context, string) (seedDB, error) { return nil, errors.New("dsn-secret") }, nil},
		{"exec", func(context.Context, string) (seedDB, error) {
			return &fakeSeedDB{execErr: errors.New("password-hash-secret")}, nil
		}, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			out := new(strings.Builder)
			db := tc.db
			open := tc.open
			if tc.name == "exec" {
				db = &fakeSeedDB{execErr: errors.New("password-hash-secret")}
				open = func(context.Context, string) (seedDB, error) { return db, nil }
			}
			err := run(context.Background(), func(k string) string { return env[k] }, nil, out, open, &fakeSeedHasher{hash: "hash"})
			if err == nil {
				t.Fatal("expected failure")
			}
			for _, secret := range []string{"dsn-secret", "user@example.com", "SuperSecret123!", "password-hash-secret"} {
				if strings.Contains(out.String(), secret) || strings.Contains(err.Error(), secret) {
					t.Fatalf("secret leaked in output/error: %q / %q", out.String(), err)
				}
			}
		})
	}
}

func TestSeedRetriesUntilMigrationsAreReady(t *testing.T) {
	env := map[string]string{"DATABASE_URL": "dsn", "SEED_USER_EMAIL": "user@example.com", "SEED_USER_PASSWORD": "SuperSecret123!"}
	readyDB := &fakeSeedDB{}
	openCalls := 0
	waitCalls := 0
	open := func(context.Context, string) (seedDB, error) {
		openCalls++
		if openCalls < 3 {
			return nil, errors.New("postgres is still starting")
		}
		return readyDB, nil
	}
	wait := func(context.Context, time.Duration) error {
		waitCalls++
		return nil
	}
	err := runWithRetry(context.Background(), func(k string) string { return env[k] }, nil, new(strings.Builder), open, &fakeSeedHasher{hash: "hash"}, wait)
	if err != nil {
		t.Fatalf("runWithRetry: %v", err)
	}
	if openCalls != 3 || waitCalls != 2 {
		t.Fatalf("retry calls = open:%d wait:%d", openCalls, waitCalls)
	}
}

func TestSeedDoesNotRetryInvalidConfiguration(t *testing.T) {
	waitCalls := 0
	err := runWithRetry(context.Background(), func(string) string { return "" }, nil, new(strings.Builder), nil, nil, func(context.Context, time.Duration) error {
		waitCalls++
		return nil
	})
	if err == nil || waitCalls != 0 {
		t.Fatalf("invalid configuration retry = %v, waits = %d", err, waitCalls)
	}
}

func TestSeedPostgresIsIdempotent(t *testing.T) {
	testcontainers.SkipIfProviderIsNotHealthy(t)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	c, err := postgrescontainer.Run(ctx, "postgres:16-alpine", postgrescontainer.WithDatabase("seed_test"), postgrescontainer.WithUsername("seed_user"), postgrescontainer.WithPassword("seed_password"), postgrescontainer.BasicWaitStrategies())
	if err != nil {
		t.Skipf("Docker unavailable: %v", err)
	}
	testcontainers.CleanupContainer(t, c)
	dsn, err := c.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	sqlDB, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })
	if err := sqlDB.PingContext(ctx); err != nil {
		t.Fatal(err)
	}
	migrations := os.DirFS("../../migrations")
	if _, err := fs.Stat(migrations, "000001_auth.sql"); err != nil {
		t.Fatal(err)
	}
	if err := migration.RunUp(ctx, sqlDB, migrations); err != nil {
		t.Fatal(err)
	}
	env := map[string]string{"DATABASE_URL": dsn, "SEED_USER_EMAIL": " Demo@Example.COM ", "SEED_USER_PASSWORD": "DemoPassword123!"}
	open := func(ctx context.Context, dsn string) (seedDB, error) { return pgxpool.New(ctx, dsn) }
	for i := 0; i < 2; i++ {
		if err := run(ctx, func(k string) string { return env[k] }, nil, new(strings.Builder), open, auth.NewPasswordHasher()); err != nil {
			t.Fatal(err)
		}
	}
	var count int
	var email, status, hash string
	if err := sqlDB.QueryRowContext(ctx, `SELECT COUNT(*), MIN(email), MIN(status), MIN(password_hash) FROM users`).Scan(&count, &email, &status, &hash); err != nil {
		t.Fatal(err)
	}
	if count != 1 || email != "demo@example.com" || status != "active" || hash == "" {
		t.Fatalf("seed row = %d %q %q hash=%t", count, email, status, hash != "")
	}
}

func secretValue(env map[string]string) string { return env["SEED_USER_PASSWORD"] }
