package migration

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"io/fs"
	"os"
	"sort"
	"strings"
	"testing"
	"testing/fstest"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/testcontainers/testcontainers-go"
	postgrescontainer "github.com/testcontainers/testcontainers-go/modules/postgres"
)

const postgresTestImage = "postgres:16-alpine"

func TestRunUpDownAndReapplyAuthMigrationOnPostgreSQL(t *testing.T) {
	testcontainers.SkipIfProviderIsNotHealthy(t)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	container, err := postgrescontainer.Run(
		ctx,
		postgresTestImage,
		postgrescontainer.WithDatabase("ecommerce_auth_test"),
		postgrescontainer.WithUsername("ecommerce_test"),
		postgrescontainer.WithPassword("ecommerce_test_password"),
		postgrescontainer.BasicWaitStrategies(),
	)
	testcontainers.CleanupContainer(t, container)
	if err != nil {
		t.Fatalf("start %s test container: %v", postgresTestImage, err)
	}

	connectionString, err := container.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatalf("build PostgreSQL connection string: %v", err)
	}

	db, err := sql.Open("pgx", connectionString)
	if err != nil {
		t.Fatalf("open PostgreSQL connection: %v", err)
	}
	t.Cleanup(func() {
		if err := db.Close(); err != nil {
			t.Errorf("close PostgreSQL connection: %v", err)
		}
	})
	if err := db.PingContext(ctx); err != nil {
		t.Fatalf("ping PostgreSQL: %v", err)
	}
	var serverVersion string
	if err := db.QueryRowContext(ctx, "SHOW server_version").Scan(&serverVersion); err != nil {
		t.Fatalf("read PostgreSQL server version: %v", err)
	}

	migrations := authMigrationFS(t)

	if err := RunUp(ctx, db, migrations); err != nil {
		t.Fatalf("apply auth migration: %v", err)
	}
	firstSchema := assertPostgreSQLUserSchema(t, ctx, db)
	assertNoRefreshFamilyPersistence(t, ctx, db)

	if err := RunDown(ctx, db, migrations); err != nil {
		t.Fatalf("roll back auth migration: %v", err)
	}
	assertAuthObjectsRemoved(t, ctx, db)
	assertNoRefreshFamilyPersistence(t, ctx, db)

	if err := RunUp(ctx, db, migrations); err != nil {
		t.Fatalf("reapply auth migration: %v", err)
	}
	reappliedSchema := assertPostgreSQLUserSchema(t, ctx, db)
	assertNoRefreshFamilyPersistence(t, ctx, db)

	if firstSchema != reappliedSchema {
		t.Fatalf("schema changed after down/reapply:\nfirst:     %s\nreapplied: %s", firstSchema, reappliedSchema)
	}
	t.Logf("verified %s (PostgreSQL %s) deterministic auth schema sha256=%s", postgresTestImage, serverVersion, firstSchema)
}

func authMigrationFS(t *testing.T) fs.FS {
	t.Helper()

	migrations := os.DirFS("../../../migrations")
	authMigration, err := fs.ReadFile(migrations, "000001_auth.sql")
	if err != nil {
		t.Fatalf("locate caller-supplied auth migration filesystem: %v", err)
	}
	return fstest.MapFS{"000001_auth.sql": &fstest.MapFile{Data: authMigration}}
}

func assertPostgreSQLUserSchema(t *testing.T, ctx context.Context, db *sql.DB) string {
	t.Helper()

	wantColumns := []string{
		"created_at|timestamp with time zone|NO|now()",
		"email|text|NO|",
		"id|uuid|NO|gen_random_uuid()",
		"password_hash|text|NO|",
		"status|text|NO|'active'::text",
		"updated_at|timestamp with time zone|NO|now()",
	}
	columns := queryCatalogRows(t, ctx, db, `
		SELECT column_name, data_type, is_nullable, COALESCE(column_default, '')
		FROM information_schema.columns
		WHERE table_schema = 'public' AND table_name = 'users'
		ORDER BY column_name`)
	assertRowsEqual(t, "users columns", columns, wantColumns)

	wantConstraints := []string{
		"users_email_normalized_check|c",
		"users_pkey|p",
		"users_status_check|c",
	}
	constraints := queryCatalogRows(t, ctx, db, `
		SELECT conname, contype::text
		FROM pg_constraint
		WHERE conrelid = 'public.users'::regclass
		ORDER BY conname`)
	assertRowsEqual(t, "users constraints", constraints, wantConstraints)

	wantIndexes := []string{
		"users_email_unique_idx|true|email",
		"users_pkey|true|id",
	}
	indexes := queryCatalogRows(t, ctx, db, `
		SELECT index_relation.relname, index.indisunique::text,
			string_agg(attribute.attname, ',' ORDER BY indexed_column.ordinality)
		FROM pg_index AS index
		JOIN pg_class AS table_relation ON table_relation.oid = index.indrelid
		JOIN pg_namespace AS namespace ON namespace.oid = table_relation.relnamespace
		JOIN pg_class AS index_relation ON index_relation.oid = index.indexrelid
		JOIN unnest(index.indkey) WITH ORDINALITY AS indexed_column(attribute_number, ordinality) ON true
		JOIN pg_attribute AS attribute
			ON attribute.attrelid = table_relation.oid
			AND attribute.attnum = indexed_column.attribute_number
		WHERE namespace.nspname = 'public' AND table_relation.relname = 'users'
		GROUP BY index_relation.relname, index.indisunique
		ORDER BY index_relation.relname`)
	assertRowsEqual(t, "users indexes", indexes, wantIndexes)
	assertUserConstraintsEnforced(t, ctx, db)

	snapshot := strings.Join(append(append(columns, constraints...), indexes...), "\n")
	digest := sha256.Sum256([]byte(snapshot))
	return hex.EncodeToString(digest[:])
}

func assertUserConstraintsEnforced(t *testing.T, ctx context.Context, db *sql.DB) {
	t.Helper()

	if _, err := db.ExecContext(ctx, `
		INSERT INTO users (email, password_hash, status)
		VALUES ('user@example.com', 'hash', 'active')`); err != nil {
		t.Fatalf("insert valid user using generated UUID and timestamps: %v", err)
	}

	invalidInserts := []struct {
		name  string
		query string
	}{
		{
			name: "normalized email check",
			query: `INSERT INTO users (email, password_hash, status)
				VALUES ('User@example.com', 'hash', 'active')`,
		},
		{
			name: "status check",
			query: `INSERT INTO users (email, password_hash, status)
				VALUES ('status@example.com', 'hash', 'pending')`,
		},
		{
			name: "unique email index",
			query: `INSERT INTO users (email, password_hash, status)
				VALUES ('user@example.com', 'different-hash', 'disabled')`,
		},
	}
	for _, invalidInsert := range invalidInserts {
		if _, err := db.ExecContext(ctx, invalidInsert.query); err == nil {
			t.Errorf("%s accepted an invalid user", invalidInsert.name)
		}
	}
}

func assertAuthObjectsRemoved(t *testing.T, ctx context.Context, db *sql.DB) {
	t.Helper()

	var usersTableCount int
	if err := db.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM information_schema.tables
		WHERE table_schema = 'public' AND table_name = 'users'`).Scan(&usersTableCount); err != nil {
		t.Fatalf("inspect users table after rollback: %v", err)
	}
	if usersTableCount != 0 {
		t.Fatalf("users table remains after rollback")
	}

	var usersIndexCount int
	if err := db.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM pg_indexes
		WHERE schemaname = 'public' AND indexname IN ('users_pkey', 'users_email_unique_idx')`).Scan(&usersIndexCount); err != nil {
		t.Fatalf("inspect users indexes after rollback: %v", err)
	}
	if usersIndexCount != 0 {
		t.Fatalf("users indexes remain after rollback: count=%d", usersIndexCount)
	}
}

func assertNoRefreshFamilyPersistence(t *testing.T, ctx context.Context, db *sql.DB) {
	t.Helper()

	forbidden := queryCatalogRows(t, ctx, db, `
		SELECT table_name, COALESCE(column_name, '')
		FROM information_schema.tables AS tables
		LEFT JOIN information_schema.columns AS columns
			USING (table_catalog, table_schema, table_name)
		WHERE tables.table_schema = 'public'
			AND (
				lower(tables.table_name) LIKE '%refresh%'
				OR lower(tables.table_name) LIKE '%token_family%'
				OR lower(tables.table_name) = 'families'
				OR lower(COALESCE(columns.column_name, '')) LIKE '%refresh%'
				OR lower(COALESCE(columns.column_name, '')) LIKE '%token_family%'
				OR lower(COALESCE(columns.column_name, '')) = 'family_id'
			)
		ORDER BY table_name, column_name`)
	if len(forbidden) != 0 {
		t.Fatalf("PostgreSQL persists Redis-owned refresh-family state: %v", forbidden)
	}
}

func queryCatalogRows(t *testing.T, ctx context.Context, db *sql.DB, query string) []string {
	t.Helper()

	rows, err := db.QueryContext(ctx, query)
	if err != nil {
		t.Fatalf("query PostgreSQL catalog: %v", err)
	}
	defer func() {
		if err := rows.Close(); err != nil {
			t.Errorf("close PostgreSQL catalog rows: %v", err)
		}
	}()

	var values []string
	for rows.Next() {
		columns, err := rows.Columns()
		if err != nil {
			t.Fatalf("read PostgreSQL catalog columns: %v", err)
		}
		row := make([]string, len(columns))
		destinations := make([]any, len(columns))
		for index := range row {
			destinations[index] = &row[index]
		}
		err = rows.Scan(destinations...)
		if err != nil {
			t.Fatalf("scan PostgreSQL catalog row: %v", err)
		}
		values = append(values, strings.Join(row, "|"))
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate PostgreSQL catalog rows: %v", err)
	}

	sort.Strings(values)
	return values
}

func assertRowsEqual(t *testing.T, name string, got, want []string) {
	t.Helper()

	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("unexpected %s:\ngot:  %v\nwant: %v", name, got, want)
	}
}
