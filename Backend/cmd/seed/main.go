// Command seed creates or updates the local development authentication user.
// Credentials are intentionally accepted only through the environment.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/mail"
	"os"
	"strings"
	"time"
	"unicode"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/vominhtri1049/learning-superpower/backend/internal/auth"
)

const upsertUserSQL = `INSERT INTO users (email, password_hash, status, created_at, updated_at)
VALUES ($1, $2, 'active', NOW(), NOW())
ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash, status = 'active', updated_at = NOW()`

var errSeedRetryable = errors.New("seed database is not ready")

const (
	seedRetryAttempts = 30
	seedRetryDelay    = time.Second
)

type seedDB interface {
	Ping(context.Context) error
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	Close()
}

type seedHasher interface{ Hash(string) (string, error) }
type seedDBFactory func(context.Context, string) (seedDB, error)

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 35*time.Second)
	defer cancel()
	if err := runWithRetry(ctx, os.Getenv, os.Stdout, os.Stderr, openSeedDB, auth.NewPasswordHasher(), waitSeedRetry); err != nil {
		// Keep command output generic: never print DSNs, credentials, hashes or addresses.
		_, _ = io.WriteString(os.Stderr, "seed failed\n")
		os.Exit(1)
	}
	_, _ = io.WriteString(os.Stdout, "seed complete\n")
}

func runWithRetry(ctx context.Context, getenv func(string) string, out, errOut io.Writer, open seedDBFactory, hasher seedHasher, wait func(context.Context, time.Duration) error) error {
	for attempt := 1; ; attempt++ {
		err := run(ctx, getenv, out, errOut, open, hasher)
		if err == nil || !errors.Is(err, errSeedRetryable) || attempt >= seedRetryAttempts {
			return err
		}
		if err := wait(ctx, seedRetryDelay); err != nil {
			return err
		}
	}
}

func waitSeedRetry(ctx context.Context, delay time.Duration) error {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-timer.C:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func openSeedDB(ctx context.Context, dsn string) (seedDB, error) {
	p, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, errors.New("database connection failed")
	}
	return p, nil
}

func run(ctx context.Context, getenv func(string) string, _ io.Writer, errOut io.Writer, open seedDBFactory, hasher seedHasher) error {
	dsn, email, password := getenv("DATABASE_URL"), getenv("SEED_USER_EMAIL"), getenv("SEED_USER_PASSWORD")
	normalized, err := normalizeEmail(email)
	if dsn == "" || err != nil || !strongPassword(password) {
		writeGeneric(errOut)
		return errors.New("required seed configuration is invalid")
	}
	if open == nil || hasher == nil {
		writeGeneric(errOut)
		return errors.New("seed dependencies are unavailable")
	}
	db, err := open(ctx, dsn)
	if err != nil || db == nil {
		writeGeneric(errOut)
		return fmt.Errorf("%w: database connection failed", errSeedRetryable)
	}
	defer db.Close()

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	err = db.Ping(pingCtx)
	cancel()
	if err != nil {
		writeGeneric(errOut)
		return fmt.Errorf("%w: database health check failed", errSeedRetryable)
	}
	hash, err := hasher.Hash(password)
	if err != nil || hash == "" {
		writeGeneric(errOut)
		return errors.New("password hashing failed")
	}
	if _, err = db.Exec(ctx, upsertUserSQL, normalized, hash); err != nil {
		writeGeneric(errOut)
		return fmt.Errorf("%w: user seed failed", errSeedRetryable)
	}
	return nil
}

func normalizeEmail(raw string) (string, error) {
	v := strings.ToLower(strings.TrimSpace(raw))
	if v == "" || len(v) > 320 {
		return "", errors.New("invalid email")
	}
	a, err := mail.ParseAddress(v)
	if err != nil || a.Address != v || !strings.Contains(v, "@") {
		return "", errors.New("invalid email")
	}
	return v, nil
}

func strongPassword(password string) bool {
	if len([]rune(password)) < 12 || len(password) > 1024 {
		return false
	}
	var letter, digit bool
	for _, r := range password {
		letter = letter || unicode.IsLetter(r)
		digit = digit || unicode.IsDigit(r)
	}
	return letter && digit
}

func writeGeneric(w io.Writer) {
	if w != nil {
		_, _ = io.WriteString(w, "seed configuration or operation failed\n")
	}
}

var _ seedDB = (*pgxpool.Pool)(nil)
