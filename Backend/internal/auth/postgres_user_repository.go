package auth

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type userRowQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

// PostgresUserRepository reads authentication credentials from PostgreSQL.
type PostgresUserRepository struct{ db userRowQuerier }

func NewPostgresUserRepository(db userRowQuerier) (*PostgresUserRepository, error) {
	if db == nil || (reflect.ValueOf(db).Kind() == reflect.Ptr && reflect.ValueOf(db).IsNil()) {
		return nil, errors.New("user repository database must not be nil")
	}
	return &PostgresUserRepository{db: db}, nil
}

const findUserByEmailSQL = `SELECT id, email, status, password_hash, created_at, updated_at FROM users WHERE email = $1`

func (r *PostgresUserRepository) FindByEmail(ctx context.Context, email string) (CredentialRecord, error) {
	if err := ctx.Err(); err != nil {
		return CredentialRecord{}, err
	}
	normalized := strings.ToLower(strings.TrimSpace(email))
	var id, storedEmail, status, hash string
	var createdAt, updatedAt time.Time
	err := r.db.QueryRow(ctx, findUserByEmailSQL, normalized).Scan(&id, &storedEmail, &status, &hash, &createdAt, &updatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return CredentialRecord{}, ErrUserNotFound
		}
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return CredentialRecord{}, err
		}
		return CredentialRecord{}, fmt.Errorf("%w: user lookup failed", ErrRepository)
	}
	if _, err := uuid.Parse(id); err != nil || normalized == "" || storedEmail != normalized || hash == "" || (UserStatus(status) != UserStatusActive && UserStatus(status) != UserStatusDisabled) || createdAt.IsZero() || updatedAt.IsZero() {
		return CredentialRecord{}, fmt.Errorf("%w: invalid user record", ErrRepository)
	}
	return CredentialRecord{ID: UserID(id), Email: storedEmail, Status: UserStatus(status), PasswordHash: hash, CreatedAt: createdAt, UpdatedAt: updatedAt}, nil
}
