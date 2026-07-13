package main

import (
	"context"
	"database/sql"
	"errors"
	"io/fs"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/redis/go-redis/v9"

	"github.com/vominhtri1049/learning-superpower/backend/internal/auth"
	"github.com/vominhtri1049/learning-superpower/backend/internal/health"
	"github.com/vominhtri1049/learning-superpower/backend/internal/platform/httpapi"
	"github.com/vominhtri1049/learning-superpower/backend/internal/platform/migration"
)

type apiConfig struct {
	databaseURL, redisURL, jwtSigningKey, jwtIssuer, jwtAudience string
	port, migrationsDir                                          string
}

func parseAPIConfig(getenv func(string) string) (apiConfig, error) {
	if getenv == nil {
		return apiConfig{}, errors.New("environment unavailable")
	}
	c := apiConfig{databaseURL: getenv("DATABASE_URL"), redisURL: getenv("REDIS_URL"), jwtSigningKey: getenv("JWT_SIGNING_KEY"), jwtIssuer: getenv("JWT_ISSUER"), jwtAudience: getenv("JWT_AUDIENCE"), port: getenv("PORT"), migrationsDir: getenv("MIGRATIONS_DIR")}
	if c.port == "" {
		c.port = "8080"
	}
	if c.migrationsDir == "" {
		c.migrationsDir = "migrations"
	}
	if c.databaseURL == "" || c.redisURL == "" || len([]byte(c.jwtSigningKey)) < 32 || c.jwtIssuer == "" || strings.TrimSpace(c.jwtIssuer) != c.jwtIssuer || c.jwtAudience == "" || strings.TrimSpace(c.jwtAudience) != c.jwtAudience {
		return apiConfig{}, errors.New("required API configuration is invalid")
	}
	if strings.TrimSpace(c.port) != c.port || c.port == "" {
		return apiConfig{}, errors.New("invalid port")
	}
	return c, nil
}

type startupDependencies struct {
	openSQL       func(context.Context, string) (*sql.DB, error)
	openPool      func(context.Context, string) (*pgxpool.Pool, error)
	newRedis      func(string) (*redis.Client, error)
	runMigrations func(context.Context, *sql.DB, fs.FS) error
}

func productionDependencies() startupDependencies {
	return startupDependencies{
		openSQL:  func(_ context.Context, dsn string) (*sql.DB, error) { return sql.Open("pgx", dsn) },
		openPool: func(ctx context.Context, dsn string) (*pgxpool.Pool, error) { return pgxpool.New(ctx, dsn) },
		newRedis: func(raw string) (*redis.Client, error) {
			opts, err := redis.ParseURL(raw)
			if err != nil {
				return nil, err
			}
			return redis.NewClient(opts), nil
		},
		runMigrations: migration.RunUp,
	}
}

type application struct {
	server *http.Server
	sqlDB  *sql.DB
	pool   *pgxpool.Pool
	redis  *redis.Client
}

func (a *application) close() {
	if a.redis != nil {
		_ = a.redis.Close()
	}
	if a.pool != nil {
		a.pool.Close()
	}
	if a.sqlDB != nil {
		_ = a.sqlDB.Close()
	}
}

func buildApplication(ctx context.Context, cfg apiConfig, deps startupDependencies) (*application, error) {
	if deps.openSQL == nil || deps.openPool == nil || deps.newRedis == nil || deps.runMigrations == nil {
		return nil, errors.New("startup dependencies unavailable")
	}
	sqlDB, err := deps.openSQL(ctx, cfg.databaseURL)
	if err != nil || sqlDB == nil {
		return nil, errors.New("database startup failed")
	}
	a := &application{sqlDB: sqlDB}
	cleanup := true
	defer func() {
		if cleanup {
			a.close()
		}
	}()
	if err := pingWithTimeout(ctx, func(c context.Context) error { return sqlDB.PingContext(c) }); err != nil {
		return nil, errors.New("database health check failed")
	}
	if err := deps.runMigrations(ctx, sqlDB, os.DirFS(cfg.migrationsDir)); err != nil {
		return nil, errors.New("database migration failed")
	}
	p, err := deps.openPool(ctx, cfg.databaseURL)
	if err != nil || p == nil {
		return nil, errors.New("database pool startup failed")
	}
	a.pool = p
	if err := pingWithTimeout(ctx, p.Ping); err != nil {
		return nil, errors.New("database pool health check failed")
	}
	r, err := deps.newRedis(cfg.redisURL)
	if err != nil || r == nil {
		return nil, errors.New("redis startup failed")
	}
	a.redis = r
	if err := pingWithTimeout(ctx, func(c context.Context) error { return r.Ping(c).Err() }); err != nil {
		return nil, errors.New("redis health check failed")
	}
	users, err := auth.NewPostgresUserRepository(p)
	if err != nil {
		return nil, errors.New("user repository startup failed")
	}
	sessions, err := auth.NewRedisRefreshRepository(r, 2*time.Second)
	if err != nil {
		return nil, errors.New("refresh repository startup failed")
	}
	issuer, err := auth.NewJWTIssuer(auth.JWTConfig{SigningKey: []byte(cfg.jwtSigningKey), Issuer: cfg.jwtIssuer, Audience: cfg.jwtAudience})
	if err != nil {
		return nil, errors.New("JWT startup failed")
	}
	service, err := auth.NewService(auth.ServiceConfig{PasswordVerifier: auth.NewPasswordHasher(), AccessTokenIssuer: issuer, RefreshTokenFactory: func() (auth.RefreshToken, error) { return auth.NewRefreshToken(nil) }, Users: users, Sessions: sessions, OperationTimeout: 5 * time.Second})
	if err != nil {
		return nil, errors.New("auth service startup failed")
	}
	handler := auth.NewHandler(service, issuer)
	server := &http.Server{Addr: ":" + cfg.port, Handler: httpapi.NewRouter(health.NewHandler(), handler), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second}
	a.server = server
	cleanup = false
	return a, nil
}

func pingWithTimeout(parent context.Context, ping func(context.Context) error) error {
	ctx, cancel := context.WithTimeout(parent, 5*time.Second)
	defer cancel()
	return ping(ctx)
}

func run(ctx context.Context, getenv func(string) string, deps startupDependencies) error {
	cfg, err := parseAPIConfig(getenv)
	if err != nil {
		return err
	}
	startupCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	a, err := buildApplication(startupCtx, cfg, deps)
	if err != nil {
		return err
	}
	defer a.close()
	serveErr := make(chan error, 1)
	go func() { serveErr <- a.server.ListenAndServe() }()
	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := a.server.Shutdown(shutdownCtx); err != nil {
			return errors.New("server shutdown failed")
		}
		return nil
	case err := <-serveErr:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			return errors.New("api stopped unexpectedly")
		}
		return nil
	}
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	cfg, err := parseAPIConfig(os.Getenv)
	if err != nil {
		slog.Error("api startup failed")
		os.Exit(1)
	}
	startupCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	a, err := buildApplication(startupCtx, cfg, productionDependencies())
	cancel()
	if err != nil {
		slog.Error("api startup failed")
		os.Exit(1)
	}
	defer a.close()
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := a.server.Shutdown(shutdownCtx); err != nil {
			slog.Error("server shutdown failed")
		}
	}()
	slog.Info("api listening", "port", cfg.port)
	if err := a.server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		slog.Error("api stopped unexpectedly")
		os.Exit(1)
	}
}
