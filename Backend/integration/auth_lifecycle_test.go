package integration

import (
	"context"
	"database/sql"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
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
)

type byteStream struct {
	mu sync.Mutex
	b  byte
}

func (r *byteStream) Read(p []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i := range p {
		p[i] = r.b
		r.b++
	}
	return len(p), nil
}

type clock struct {
	mu  sync.Mutex
	now time.Time
}

func (c *clock) Now() time.Time      { c.mu.Lock(); defer c.mu.Unlock(); return c.now }
func (c *clock) Add(d time.Duration) { c.mu.Lock(); c.now = c.now.Add(d); c.mu.Unlock() }

type authHTTPResponse struct {
	User struct {
		ID     string `json:"id"`
		Email  string `json:"email"`
		Status string `json:"status"`
	} `json:"user"`
	Tokens struct {
		AccessToken     string    `json:"access_token"`
		RefreshToken    string    `json:"refresh_token"`
		AccessExpiresAt time.Time `json:"access_expires_at"`
	} `json:"tokens"`
}
type authError struct {
	Code string `json:"code"`
}

func TestAuthLifecycleEndToEnd(t *testing.T) {
	testcontainers.SkipIfProviderIsNotHealthy(t)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	pg, err := postgrescontainer.Run(ctx, "postgres:16-alpine", postgrescontainer.WithDatabase("ecommerce_auth_test"), postgrescontainer.WithUsername("ecommerce_test"), postgrescontainer.WithPassword("ecommerce_test_password"), postgrescontainer.BasicWaitStrategies())
	testcontainers.CleanupContainer(t, pg)
	if err != nil {
		t.Skipf("Docker unavailable: %v", err)
	}
	pgURL, err := pg.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	sqlDB, err := sql.Open("pgx", pgURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })
	if err := sqlDB.PingContext(ctx); err != nil {
		t.Fatal(err)
	}
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
	const uid = "550e8400-e29b-41d4-a716-446655440000"
	if _, err = pool.Exec(ctx, `INSERT INTO users (id,email,password_hash) VALUES ($1,$2,$3)`, uid, "user@example.com", hash); err != nil {
		t.Fatal(err)
	}

	rc, err := rediscontainer.Run(ctx, "redis:7-alpine", testcontainers.WithCmdArgs("redis-server", "--requirepass", "integration-secret"))
	testcontainers.CleanupContainer(t, rc)
	if err != nil {
		t.Skipf("Docker unavailable: %v", err)
	}
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
	if err := redisClient.Ping(ctx).Err(); err != nil {
		t.Fatal(err)
	}
	users, err := auth.NewPostgresUserRepository(pool)
	if err != nil {
		t.Fatal(err)
	}
	sessions, err := auth.NewRedisRefreshRepository(redisClient, 3*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	// Redis validates TTLs against wall-clock time; freeze the injected clock at
	// the current UTC second so production stores and deterministic JWTs agree.
	cl := &clock{now: time.Now().UTC().Truncate(time.Second)}
	stream := &byteStream{b: 1}
	issuer, err := auth.NewJWTIssuer(auth.JWTConfig{SigningKey: []byte("01234567890123456789012345678901"), Issuer: "ecommerce", Audience: "ios", Clock: cl.Now, Random: stream})
	if err != nil {
		t.Fatal(err)
	}
	counter := 0
	var mu sync.Mutex
	refreshFactory := func() (auth.RefreshToken, error) {
		mu.Lock()
		defer mu.Unlock()
		counter++
		return auth.NewRefreshToken(&byteStream{b: byte(counter)})
	}
	familyFactory := func() (string, error) {
		mu.Lock()
		defer mu.Unlock()
		counter++
		return "family-integration-" + string(rune('a'+counter)), nil
	}
	service, err := auth.NewService(auth.ServiceConfig{PasswordVerifier: hasher, AccessTokenIssuer: issuer, RefreshTokenFactory: refreshFactory, FamilyIDFactory: familyFactory, Users: users, Sessions: sessions, Clock: cl.Now, RefreshLifetime: time.Hour, OperationTimeout: 5 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(httpapi.NewRouter(health.NewHandler(), auth.NewHandler(service, issuer)))
	defer server.Close()
	do := func(method, path string, body io.Reader, bearer string) *http.Response {
		req, _ := http.NewRequestWithContext(ctx, method, server.URL+path, body)
		req.Header.Set("Content-Type", "application/json")
		if bearer != "" {
			req.Header.Set("Authorization", "Bearer "+bearer)
		}
		resp, e := http.DefaultClient.Do(req)
		if e != nil {
			t.Fatal(e)
		}
		return resp
	}
	login := do(http.MethodPost, "/v1/auth/login", jsonReader(`{"email":"user@example.com","password":"correct horse battery staple"}`), "")
	if login.StatusCode != http.StatusOK {
		t.Fatalf("login status=%d", login.StatusCode)
	}
	var first authHTTPResponse
	decode(t, login, &first)
	if first.User.ID != uid || first.Tokens.RefreshToken == "" {
		t.Fatalf("invalid login DTO: %#v", first)
	}
	claims, err := issuer.Verify(first.Tokens.AccessToken)
	if err != nil {
		t.Fatal(err)
	}
	if claims.ExpiresAt.Time.Sub(claims.IssuedAt.Time) != time.Minute {
		t.Fatalf("access lifetime=%v", claims.ExpiresAt.Time.Sub(claims.IssuedAt.Time))
	}
	oldRefresh := first.Tokens.RefreshToken
	refresh := do(http.MethodPost, "/v1/auth/refresh", jsonReader(`{"refresh_token":"`+oldRefresh+`"}`), "")
	if refresh.StatusCode != http.StatusOK {
		t.Fatalf("refresh status=%d", refresh.StatusCode)
	}
	var rotated authHTTPResponse
	decode(t, refresh, &rotated)
	if rotated.Tokens.RefreshToken == oldRefresh {
		t.Fatal("refresh token was not rotated")
	}
	reuse := do(http.MethodPost, "/v1/auth/refresh", jsonReader(`{"refresh_token":"`+oldRefresh+`"}`), "")
	assertError(t, reuse, http.StatusUnauthorized, "AUTH_REFRESH_REJECTED")
	rotatedAgain := do(http.MethodPost, "/v1/auth/refresh", jsonReader(`{"refresh_token":"`+rotated.Tokens.RefreshToken+`"}`), "")
	assertError(t, rotatedAgain, http.StatusUnauthorized, "AUTH_REFRESH_REJECTED")
	second := do(http.MethodPost, "/v1/auth/login", jsonReader(`{"email":"user@example.com","password":"correct horse battery staple"}`), "")
	if second.StatusCode != http.StatusOK {
		t.Fatalf("second login status=%d", second.StatusCode)
	}
	var fresh authHTTPResponse
	decode(t, second, &fresh)
	logout := do(http.MethodPost, "/v1/auth/logout", nil, fresh.Tokens.AccessToken)
	if logout.StatusCode != http.StatusNoContent {
		t.Fatalf("logout status=%d", logout.StatusCode)
	}
	postLogout := do(http.MethodPost, "/v1/auth/refresh", jsonReader(`{"refresh_token":"`+fresh.Tokens.RefreshToken+`"}`), "")
	assertError(t, postLogout, http.StatusUnauthorized, "AUTH_REFRESH_REJECTED")
	invalid := do(http.MethodPost, "/v1/auth/login", jsonReader(`{"email":"user@example.com","password":"wrong"}`), "")
	assertError(t, invalid, http.StatusUnauthorized, "AUTH_AUTHENTICATION_FAILED")
	missingSecret := do(http.MethodPost, "/v1/auth/login", jsonReader(`{"email":"user@example.com"}`), "")
	assertError(t, missingSecret, http.StatusBadRequest, "AUTH_INVALID_REQUEST")
	cl.Add(time.Minute)
	if _, err := issuer.Verify(first.Tokens.AccessToken); err == nil {
		t.Fatal("expired access token accepted")
	}
}

func jsonReader(v string) io.Reader { return strings.NewReader(v) }
func decode(t *testing.T, r *http.Response, dst any) {
	t.Helper()
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		t.Fatal(err)
	}
}
func assertError(t *testing.T, r *http.Response, status int, code string) {
	t.Helper()
	var e authError
	decode(t, r, &e)
	if r.StatusCode != status || e.Code != code {
		t.Fatalf("error status=%d code=%q want %d/%q", r.StatusCode, e.Code, status, code)
	}
}
