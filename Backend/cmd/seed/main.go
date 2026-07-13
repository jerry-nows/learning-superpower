// Command seed creates or updates the local development authentication user.
// Credentials are intentionally accepted only through the environment.
package main

import (
	"context"
	"errors"
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

type seedDB interface {
	Ping(context.Context) error
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	Close()
}

type seedHasher interface{ Hash(string) (string, error) }
type seedDBFactory func(context.Context, string) (seedDB, error)

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := run(ctx, os.Getenv, os.Stdout, os.Stderr, openSeedDB, auth.NewPasswordHasher()); err != nil {
		// Keep command output generic: never print DSNs, credentials, hashes or addresses.
		_, _ = io.WriteString(os.Stderr, "seed failed\n")
		os.Exit(1)
	}
	_, _ = io.WriteString(os.Stdout, "seed complete\n")
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
		return errors.New("database connection failed")
	}
	defer db.Close()

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	err = db.Ping(pingCtx)
	cancel()
	if err != nil {
		writeGeneric(errOut)
		return errors.New("database health check failed")
	}
	hash, err := hasher.Hash(password)
	if err != nil || hash == "" {
		writeGeneric(errOut)
		return errors.New("password hashing failed")
	}
	if _, err = db.Exec(ctx, upsertUserSQL, normalized, hash); err != nil {
		writeGeneric(errOut)
		return errors.New("user seed failed")
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
