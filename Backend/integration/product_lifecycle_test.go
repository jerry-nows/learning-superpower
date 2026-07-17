package integration

import (
	"context"
	"database/sql"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/redis/go-redis/v9"
	"github.com/testcontainers/testcontainers-go"
	postgrescontainer "github.com/testcontainers/testcontainers-go/modules/postgres"
	rediscontainer "github.com/testcontainers/testcontainers-go/modules/redis"
	"github.com/vominhtri1049/learning-superpower/backend/internal/auth"
	"github.com/vominhtri1049/learning-superpower/backend/internal/health"
	"github.com/vominhtri1049/learning-superpower/backend/internal/platform/httpapi"
	"github.com/vominhtri1049/learning-superpower/backend/internal/platform/migration"
	"github.com/vominhtri1049/learning-superpower/backend/internal/product"
)

func TestProductLifecycleEndToEnd(t *testing.T) {
	testcontainers.SkipIfProviderIsNotHealthy(t)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	pg, err := postgrescontainer.Run(ctx, "postgres:16-alpine",
		postgrescontainer.WithDatabase("ecommerce_product_test"),
		postgrescontainer.WithUsername("ecommerce_test"),
		postgrescontainer.WithPassword("ecommerce_test_password"),
		postgrescontainer.BasicWaitStrategies(),
	)
	if err != nil {
		t.Skipf("Docker unavailable: %v", err)
	}
	testcontainers.CleanupContainer(t, pg)
	pgURL, err := pg.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	sqlDB, err := sql.Open("pgx", pgURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })
	if err := migration.RunUp(ctx, sqlDB, os.DirFS(filepath.Join("..", "migrations"))); err != nil {
		t.Fatal(err)
	}

	pool, err := pgxpool.New(ctx, pgURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	hasher := auth.NewPasswordHasher()
	hash, err := hasher.Hash("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	const userID = "550e8400-e29b-41d4-a716-446655440000"
	if _, err := pool.Exec(ctx, `INSERT INTO users (id,email,password_hash) VALUES ($1,$2,$3)`, userID, "user@example.com", hash); err != nil {
		t.Fatal(err)
	}
	const categoryID = "00000000-0000-4000-8000-000000000001"
	if _, err := pool.Exec(ctx, `INSERT INTO categories (id,name,slug) VALUES ($1,$2,$3)`, categoryID, "Electronics", "electronics"); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO products (id,category_id,name,description,price,currency,stock,status,image_url) VALUES ($1,$2,$3,$4,$5,'VND',$6,'active',$7),($8,$2,$9,$10,$11,'VND',$12,'active',$13)`,
		"00000000-0000-4000-8000-000000000101", categoryID, "Wireless Headphones", "Noise-isolating Bluetooth headphones", 1299000, 42, "https://example.invalid/headphones.jpg",
		"00000000-0000-4000-8000-000000000102", "USB-C Hub", "Six-port aluminium USB-C hub", 699000, 18, "https://example.invalid/hub.jpg"); err != nil {
		t.Fatal(err)
	}

	rc, err := rediscontainer.Run(ctx, "redis:7-alpine", testcontainers.WithCmdArgs("redis-server", "--requirepass", "integration-secret"))
	if err != nil {
		t.Skipf("Docker unavailable: %v", err)
	}
	testcontainers.CleanupContainer(t, rc)
	redisURL, err := rc.ConnectionString(ctx)
	if err != nil {
		t.Fatal(err)
	}
	opts, err := redis.ParseURL(redisURL)
	if err != nil {
		t.Fatal(err)
	}
	opts.Password = "integration-secret"
	redisClient := redis.NewClient(opts)
	t.Cleanup(func() { _ = redisClient.Close() })

	users, err := auth.NewPostgresUserRepository(pool)
	if err != nil {
		t.Fatal(err)
	}
	sessions, err := auth.NewRedisRefreshRepository(redisClient, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	issuer, err := auth.NewJWTIssuer(auth.JWTConfig{SigningKey: []byte("01234567890123456789012345678901"), Issuer: "ecommerce", Audience: "ios"})
	if err != nil {
		t.Fatal(err)
	}
	service, err := auth.NewService(auth.ServiceConfig{PasswordVerifier: hasher, AccessTokenIssuer: issuer, RefreshTokenFactory: func() (auth.RefreshToken, error) { return auth.NewRefreshToken(nil) }, Users: users, Sessions: sessions, OperationTimeout: 5 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	products, err := product.NewPostgresProductRepository(pool)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(httpapi.NewRouter(health.NewHandler(), auth.NewHandler(service, issuer), product.NewHandler(products, issuer)))
	defer server.Close()

	loginBody := jsonReader(`{"email":"user@example.com","password":"correct horse battery staple"}`)
	loginReq, _ := http.NewRequestWithContext(ctx, http.MethodPost, server.URL+"/v1/auth/login", loginBody)
	loginReq.Header.Set("Content-Type", "application/json")
	login, err := http.DefaultClient.Do(loginReq)
	if err != nil {
		t.Fatal(err)
	}
	if login.StatusCode != http.StatusOK {
		t.Fatalf("login status=%d", login.StatusCode)
	}
	var authResponse authHTTPResponse
	decode(t, login, &authResponse)
	if authResponse.Tokens.AccessToken == "" {
		t.Fatal("login did not return access token")
	}

	do := func(path string) *http.Response {
		req, _ := http.NewRequestWithContext(ctx, http.MethodGet, server.URL+path, nil)
		req.Header.Set("Authorization", "Bearer "+authResponse.Tokens.AccessToken)
		resp, requestErr := http.DefaultClient.Do(req)
		if requestErr != nil {
			t.Fatal(requestErr)
		}
		return resp
	}
	var page product.ProductPage
	list := do("/v1/products?page=1&page_size=10&sort=name_asc")
	if list.StatusCode != http.StatusOK {
		t.Fatalf("list status=%d", list.StatusCode)
	}
	decode(t, list, &page)
	if page.Total != 2 || len(page.Items) != 2 || page.Items[0].Name != "USB-C Hub" {
		t.Fatalf("unexpected product page: %#v", page)
	}
	var search product.ProductPage
	searchResponse := do("/v1/products?search=headphones")
	if searchResponse.StatusCode != http.StatusOK {
		t.Fatalf("search status=%d", searchResponse.StatusCode)
	}
	decode(t, searchResponse, &search)
	if search.Total != 1 || len(search.Items) != 1 || search.Items[0].ID != "00000000-0000-4000-8000-000000000101" {
		t.Fatalf("unexpected search result: %#v", search)
	}
	detail := do("/v1/products/00000000-0000-4000-8000-000000000101")
	if detail.StatusCode != http.StatusOK {
		t.Fatalf("detail status=%d", detail.StatusCode)
	}
	var item product.Product
	decode(t, detail, &item)
	if item.Name != "Wireless Headphones" || item.Stock != 42 {
		t.Fatalf("unexpected detail: %#v", item)
	}
}
