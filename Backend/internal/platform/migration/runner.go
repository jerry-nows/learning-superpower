// Package migration applies versioned PostgreSQL schema migrations.
package migration

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io/fs"

	"github.com/pressly/goose/v3"
)

var (
	// ErrNilDatabase indicates that a migration operation was called without a database.
	ErrNilDatabase = errors.New("migration database must not be nil")
	// ErrNilMigrationFS indicates that a migration operation was called without migration files.
	ErrNilMigrationFS = errors.New("migration filesystem must not be nil")
)

// RunUp applies every pending migration in version order.
func RunUp(ctx context.Context, db *sql.DB, migrationFS fs.FS) error {
	provider, err := newProvider(db, migrationFS)
	if err != nil {
		return fmt.Errorf("run migrations up: %w", err)
	}

	if _, err := provider.Up(ctx); err != nil {
		return fmt.Errorf("run migrations up: %w", err)
	}

	return nil
}

// RunDown rolls back the most recently applied migration.
func RunDown(ctx context.Context, db *sql.DB, migrationFS fs.FS) error {
	provider, err := newProvider(db, migrationFS)
	if err != nil {
		return fmt.Errorf("run migrations down: %w", err)
	}

	if _, err := provider.Down(ctx); err != nil {
		return fmt.Errorf("run migrations down: %w", err)
	}

	return nil
}

func newProvider(db *sql.DB, migrationFS fs.FS) (*goose.Provider, error) {
	if db == nil {
		return nil, ErrNilDatabase
	}
	if migrationFS == nil {
		return nil, ErrNilMigrationFS
	}

	provider, err := goose.NewProvider(
		goose.DialectPostgres,
		db,
		migrationFS,
		goose.WithDisableGlobalRegistry(true),
	)
	if err != nil {
		return nil, fmt.Errorf("create migration provider: %w", err)
	}

	return provider, nil
}
