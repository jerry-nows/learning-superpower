package auth

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

type fakeUserRow struct {
	values []any
	err    error
}

func (r fakeUserRow) Scan(dest ...any) error {
	if r.err != nil {
		return r.err
	}
	for i := range dest {
		switch d := dest[i].(type) {
		case *string:
			*d = r.values[i].(string)
		case *time.Time:
			*d = r.values[i].(time.Time)
		default:
			return errors.New("unsupported destination")
		}
	}
	return nil
}

func TestPostgresUserRepositoryFindByEmail(t *testing.T) {
	// This compile-time contract intentionally uses the production pgx.Row type.
	q := &contractUserQuerier{row: fakeUserRow{values: []any{"550e8400-e29b-41d4-a716-446655440000", "user@example.com", "active", "hash", time.Unix(1, 0), time.Unix(2, 0)}}}
	r, err := NewPostgresUserRepository(q)
	if err != nil {
		t.Fatal(err)
	}
	got, err := r.FindByEmail(context.Background(), " User@Example.COM ")
	if err != nil {
		t.Fatal(err)
	}
	if got.ID != UserID("550e8400-e29b-41d4-a716-446655440000") || got.Email != "user@example.com" || got.PasswordHash != "hash" || q.args[0] != "user@example.com" {
		t.Fatalf("unexpected result: %#v", got)
	}
}

func TestPostgresUserRepositoryMapsErrorsSafely(t *testing.T) {
	q := &contractUserQuerier{row: fakeUserRow{err: errors.New("db details password=secret")}}
	r, err := NewPostgresUserRepository(q)
	if err != nil {
		t.Fatal(err)
	}
	_, err = r.FindByEmail(context.Background(), "user@example.com")
	if !errors.Is(err, ErrRepository) || errors.Is(err, errors.New("db details password=secret")) || len(err.Error()) > 80 {
		t.Fatalf("unsafe mapping: %v", err)
	}
}

// Keep the mock's method signature tied to pgx.Row through the adapter below.
type contractUserQuerier struct {
	row  fakeUserRow
	args []any
}

func (q *contractUserQuerier) QueryRow(_ context.Context, _ string, args ...any) pgx.Row {
	q.args = args
	return q.row
}
