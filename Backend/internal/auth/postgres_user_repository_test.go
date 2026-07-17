package auth

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/testcontainers/testcontainers-go"
	postgrescontainer "github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/vominhtri1049/learning-superpower/backend/internal/platform/migration"
)

const deterministicArgon2PHC = "$argon2id$v=19$m=65536,t=3,p=1$YWJjZGVmZ2hpamtsbW5vcA$YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXk"

func TestPostgresUserRepositoryIntegration(t *testing.T) {
	testcontainers.SkipIfProviderIsNotHealthy(t)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	container, err := postgrescontainer.Run(ctx, "postgres:16-alpine",
		postgrescontainer.WithDatabase("ecommerce_auth_test"),
		postgrescontainer.WithUsername("ecommerce_test"),
		postgrescontainer.WithPassword("ecommerce_test_password"),
		postgrescontainer.BasicWaitStrategies(),
	)
	testcontainers.CleanupContainer(t, container)
	if err != nil {
		t.Fatalf("start postgres testcontainer (Docker required): %v", err)
	}
	connString, err := container.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatalf("connection string: %v", err)
	}

	// Migration runner uses database/sql; repository uses pgxpool against the same DB.
	sqlDB, err := sql.Open("pgx", connString)
	if err != nil {
		t.Fatalf("open migration connection: %v", err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })
	if err := sqlDB.PingContext(ctx); err != nil {
		t.Fatalf("ping postgres: %v", err)
	}
	migrations := osDirFS(t, filepath.Join("..", "..", "migrations"))
	if err := migration.RunUp(ctx, sqlDB, migrations); err != nil {
		t.Fatalf("apply auth migration: %v", err)
	}

	pool, err := pgxpool.New(ctx, connString)
	if err != nil {
		t.Fatalf("open pgxpool: %v", err)
	}
	t.Cleanup(pool.Close)
	if err := pool.Ping(ctx); err != nil {
		t.Fatalf("ping pgxpool: %v", err)
	}

	created := time.Date(2025, 1, 2, 3, 4, 5, 0, time.UTC)
	updated := created.Add(time.Hour)
	const id = "550e8400-e29b-41d4-a716-446655440000"
	_, err = pool.Exec(ctx, `INSERT INTO users (id,email,status,password_hash,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$6)`, id, "user@example.com", "active", deterministicArgon2PHC, created, updated)
	if err != nil {
		t.Fatalf("insert deterministic user: %v", err)
	}
	repo, err := NewPostgresUserRepository(pool)
	if err != nil {
		t.Fatal(err)
	}

	got, err := repo.FindByEmail(ctx, "  USER@Example.COM  ")
	if err != nil {
		t.Fatalf("normalized lookup: %v", err)
	}
	if got.ID != UserID(id) || got.Email != "user@example.com" || got.Status != UserStatusActive || got.PasswordHash != deterministicArgon2PHC || !got.CreatedAt.Equal(created) || !got.UpdatedAt.Equal(updated) {
		t.Fatalf("unexpected credential record: %#v", got)
	}
	public := got.PublicUser()
	b, err := json.Marshal(public)
	if err != nil {
		t.Fatal(err)
	}
	if string(b) == "" || string(b) == "null" || contains(string(b), "password") || contains(string(b), "argon2") {
		t.Fatalf("public projection leaked credential data: %s", b)
	}
	if _, err := repo.FindByEmail(ctx, "missing@example.com"); !errors.Is(err, ErrUserNotFound) {
		t.Fatalf("unknown user error = %v, want ErrUserNotFound", err)
	}

	cancelled, cancel := context.WithCancel(ctx)
	cancel()
	if _, err := repo.FindByEmail(cancelled, "user@example.com"); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancelled context error = %v", err)
	}
	deadline, expire := context.WithDeadline(ctx, time.Now().Add(-time.Second))
	defer expire()
	if _, err := repo.FindByEmail(deadline, "user@example.com"); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("deadline context error = %v", err)
	}
}

func osDirFS(t *testing.T, path string) fs.FS {
	t.Helper()
	fsys := os.DirFS(path)
	if _, err := fs.Stat(fsys, "000001_auth.sql"); err != nil {
		t.Fatalf("locate migration at %s: %v", path, err)
	}
	return fsys
}

func contains(s, part string) bool {
	for i := 0; i+len(part) <= len(s); i++ {
		if s[i:i+len(part)] == part {
			return true
		}
	}
	return false
}
