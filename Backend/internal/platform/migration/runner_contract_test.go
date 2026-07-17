package migration

import (
	"context"
	"database/sql"
	"errors"
	"testing"
	"testing/fstest"
)

func TestRunOperationsRejectInvalidDependencies(t *testing.T) {
	t.Parallel()

	migrations := fstest.MapFS{
		"000001_example.sql": &fstest.MapFile{Data: []byte("-- +goose Up\nSELECT 1;\n-- +goose Down\nSELECT 1;\n")},
	}

	tests := []struct {
		name    string
		run     func() error
		wantErr error
	}{
		{
			name: "up rejects nil database",
			run: func() error {
				return RunUp(context.Background(), nil, migrations)
			},
			wantErr: ErrNilDatabase,
		},
		{
			name: "down rejects nil database",
			run: func() error {
				return RunDown(context.Background(), nil, migrations)
			},
			wantErr: ErrNilDatabase,
		},
		{
			name: "up rejects nil migration filesystem",
			run: func() error {
				return RunUp(context.Background(), &sql.DB{}, nil)
			},
			wantErr: ErrNilMigrationFS,
		},
		{
			name: "down rejects nil migration filesystem",
			run: func() error {
				return RunDown(context.Background(), &sql.DB{}, nil)
			},
			wantErr: ErrNilMigrationFS,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			if err := test.run(); !errors.Is(err, test.wantErr) {
				t.Fatalf("expected error %v, got %v", test.wantErr, err)
			}
		})
	}
}
