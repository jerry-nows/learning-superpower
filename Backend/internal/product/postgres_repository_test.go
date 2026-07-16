package product

import (
	"context"
	"database/sql"
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

func TestNewPostgresProductRepositoryRejectsNilDatabase(t *testing.T) {
	if _, err := NewPostgresProductRepository(nil); err == nil {
		t.Fatal("nil database was accepted")
	}
}

func TestProductSortSQLIsAllowListed(t *testing.T) {
	if _, ok := productSortSQL[ProductSort(`name; DROP TABLE products; --`)]; ok {
		t.Fatal("untrusted sort value entered SQL allow-list")
	}
}

func TestPostgresProductRepositoryIntegration(t *testing.T) {
	testcontainers.SkipIfProviderIsNotHealthy(t)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	container, err := postgrescontainer.Run(ctx, "postgres:16-alpine",
		postgrescontainer.WithDatabase("ecommerce_product_test"),
		postgrescontainer.WithUsername("ecommerce_test"),
		postgrescontainer.WithPassword("ecommerce_test_password"),
		postgrescontainer.BasicWaitStrategies(),
	)
	testcontainers.CleanupContainer(t, container)
	if err != nil {
		t.Skipf("Docker unavailable: %v", err)
	}
	connString, err := container.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	sqlDB, err := sql.Open("pgx", connString)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })
	if err := migration.RunUp(ctx, sqlDB, migrationFS(t)); err != nil {
		t.Fatal(err)
	}
	pool, err := pgxpool.New(ctx, connString)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	const category = "550e8400-e29b-41d4-a716-446655440001"
	if _, err := pool.Exec(ctx, `INSERT INTO categories (id,name,slug) VALUES ($1,$2,$3)`, category, "Coffee", "coffee"); err != nil {
		t.Fatal(err)
	}
	created := time.Date(2026, 7, 16, 10, 0, 0, 0, time.UTC)
	for _, item := range []struct {
		id, name    string
		description string
		price       int64
		stock       int
	}{
		{"550e8400-e29b-41d4-a716-446655440011", "Arabica", "Arabica beans", 100, 4},
		{"550e8400-e29b-41d4-a716-446655440012", "Robusta", "Robusta beans", 200, 8},
		{"550e8400-e29b-41d4-a716-446655440013", "Tea", "Tea leaves", 50, 2},
	} {
		if _, err := pool.Exec(ctx, `INSERT INTO products (id,category_id,name,description,price,stock,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$7)`, item.id, category, item.name, item.description, item.price, item.stock, created); err != nil {
			t.Fatal(err)
		}
	}
	repo, err := NewPostgresProductRepository(pool)
	if err != nil {
		t.Fatal(err)
	}
	page, err := repo.List(ctx, ProductQuery{Page: 1, PageSize: 2, Search: "bean", CategoryID: category, Sort: ProductSortPriceDescending})
	if err != nil || page.Total != 2 || len(page.Items) != 2 || page.Items[0].Name != "Robusta" || page.HasNext {
		t.Fatalf("filtered page = %#v, err %v", page, err)
	}
	page, err = repo.List(ctx, ProductQuery{Page: 1, PageSize: 1, Sort: ProductSortPriceAscending})
	if err != nil || page.Items[0].Name != "Tea" {
		t.Fatalf("price sort page = %#v, err %v", page, err)
	}
	product, err := repo.FindByID(ctx, ProductID("550e8400-e29b-41d4-a716-446655440011"))
	if err != nil || product.Name != "Arabica" {
		t.Fatalf("find product = %#v, err %v", product, err)
	}
	if _, err := repo.FindByID(ctx, "missing"); !errors.Is(err, ErrProductNotFound) {
		t.Fatalf("missing product error = %v", err)
	}
	categories, err := repo.ListCategories(ctx)
	if err != nil || len(categories) != 1 || categories[0].Name != "Coffee" {
		t.Fatalf("categories = %#v, err %v", categories, err)
	}
	stock, err := repo.GetStock(ctx, ProductID("550e8400-e29b-41d4-a716-446655440011"))
	if err != nil || stock.Available != 4 {
		t.Fatalf("stock = %#v, err %v", stock, err)
	}
	cancelled, cancelChild := context.WithCancel(ctx)
	cancelChild()
	if _, err := repo.List(cancelled, ProductQuery{}); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancelled list error = %v", err)
	}
}

func migrationFS(t *testing.T) fs.FS {
	t.Helper()
	f := os.DirFS(filepath.Join("..", "..", "migrations"))
	if _, err := fs.Stat(f, "000002_product.sql"); err != nil {
		t.Fatal(err)
	}
	return f
}
