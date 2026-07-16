// Command seed creates or updates the local development user and catalog.
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

// Fixed UUIDs make local fixtures stable across restarts. The seed only writes
// non-sensitive demo catalog data; credentials remain environment-only.
type catalogCategory struct {
	id   string
	name string
	slug string
}

type catalogProduct struct {
	id, categoryID, name, description, imageURL string
	price, stock                                int64
}

var seedCategories = []catalogCategory{
	{id: "00000000-0000-4000-8000-000000000001", name: "Electronics", slug: "electronics"},
	{id: "00000000-0000-4000-8000-000000000002", name: "Home & Living", slug: "home-living"},
	{id: "00000000-0000-4000-8000-000000000003", name: "Fashion", slug: "fashion"},
}

var seedProducts = []catalogProduct{
	{id: "00000000-0000-4000-8000-000000000101", categoryID: seedCategories[0].id, name: "Wireless Headphones", description: "Noise-isolating Bluetooth headphones", price: 1299000, stock: 42, imageURL: "https://example.invalid/products/wireless-headphones.jpg"},
	{id: "00000000-0000-4000-8000-000000000102", categoryID: seedCategories[0].id, name: "USB-C Hub", description: "Six-port aluminium USB-C hub", price: 699000, stock: 18, imageURL: "https://example.invalid/products/usb-c-hub.jpg"},
	{id: "00000000-0000-4000-8000-000000000201", categoryID: seedCategories[1].id, name: "Ceramic Coffee Set", description: "Hand-finished cups for everyday coffee", price: 459000, stock: 25, imageURL: "https://example.invalid/products/ceramic-coffee-set.jpg"},
	{id: "00000000-0000-4000-8000-000000000202", categoryID: seedCategories[1].id, name: "Linen Throw Pillow", description: "Soft natural linen cushion cover", price: 219000, stock: 31, imageURL: "https://example.invalid/products/linen-throw-pillow.jpg"},
	{id: "00000000-0000-4000-8000-000000000301", categoryID: seedCategories[2].id, name: "Everyday Canvas Tote", description: "Reusable cotton canvas tote bag", price: 159000, stock: 64, imageURL: "https://example.invalid/products/canvas-tote.jpg"},
	{id: "00000000-0000-4000-8000-000000000302", categoryID: seedCategories[2].id, name: "Classic Cotton Cap", description: "Breathable cotton cap with adjustable strap", price: 189000, stock: 37, imageURL: "https://example.invalid/products/cotton-cap.jpg"},
}

const upsertCategorySQL = `INSERT INTO categories (id, name, slug, created_at, updated_at)
VALUES ($1, $2, $3, NOW(), NOW())
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, slug = EXCLUDED.slug, updated_at = NOW()`

const upsertProductSQL = `INSERT INTO products (id, category_id, name, description, price, currency, stock, status, image_url, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, 'VND', $6, 'active', $7, NOW(), NOW())
ON CONFLICT (id) DO UPDATE SET category_id = EXCLUDED.category_id, name = EXCLUDED.name, description = EXCLUDED.description, price = EXCLUDED.price, currency = EXCLUDED.currency, stock = EXCLUDED.stock, status = 'active', image_url = EXCLUDED.image_url, updated_at = NOW()`

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
	if err := seedCatalog(ctx, db); err != nil {
		writeGeneric(errOut)
		return fmt.Errorf("%w: catalog seed failed", errSeedRetryable)
	}
	if _, err = db.Exec(ctx, upsertUserSQL, normalized, hash); err != nil {
		writeGeneric(errOut)
		return fmt.Errorf("%w: user seed failed", errSeedRetryable)
	}
	return nil
}

func seedCatalog(ctx context.Context, db seedDB) error {
	for _, category := range seedCategories {
		if _, err := db.Exec(ctx, upsertCategorySQL, category.id, category.name, category.slug); err != nil {
			return err
		}
	}
	for _, product := range seedProducts {
		if _, err := db.Exec(ctx, upsertProductSQL, product.id, product.categoryID, product.name, product.description, product.price, product.stock, product.imageURL); err != nil {
			return err
		}
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
