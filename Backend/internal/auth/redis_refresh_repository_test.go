package auth

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/testcontainers/testcontainers-go"
	rediscontainer "github.com/testcontainers/testcontainers-go/modules/redis"
)

const redisRefreshTestPassword = "cr140-only-password"

func newRedisRefreshRepository(t *testing.T) (*RedisRefreshRepository, *redis.Client, context.Context) {
	t.Helper()
	testcontainers.SkipIfProviderIsNotHealthy(t)
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	t.Cleanup(cancel)
	container, err := rediscontainer.Run(ctx, "redis:7-alpine",
		testcontainers.WithCmdArgs("redis-server", "--requirepass", redisRefreshTestPassword),
	)
	testcontainers.CleanupContainer(t, container)
	if err != nil {
		t.Skipf("Docker unavailable; skipping authenticated Redis integration test: %v", err)
	}
	endpoint, err := container.ConnectionString(ctx)
	if err != nil {
		t.Fatal(err)
	}
	options, err := redis.ParseURL(endpoint)
	if err != nil {
		t.Fatal(err)
	}
	options.Password = redisRefreshTestPassword
	client := redis.NewClient(options)
	t.Cleanup(func() { _ = client.Close() })
	if err := client.Ping(ctx).Err(); err != nil {
		t.Fatal(err)
	}
	repo, err := NewRedisRefreshRepository(client, 3*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	return repo, client, ctx
}

func refreshDigest(label string) [sha256.Size]byte { return sha256.Sum256([]byte(label)) }
func refreshSession(label, family string, expires time.Time) RefreshSession {
	return RefreshSession{FamilyID: family, UserID: UserID("user-cr140"), TokenDigest: refreshDigest(label), ExpiresAt: expires}
}

func TestRedisRefreshRepositoryAuthenticatedIntegration(t *testing.T) {
	repo, client, ctx := newRedisRefreshRepository(t)
	now := time.Now().UTC()

	t.Run("create rotate and atomic concurrent reuse", func(t *testing.T) {
		lifecycleOld := refreshSession("old-lifecycle", "family-lifecycle", now.Add(10*time.Minute))
		if err := repo.Create(ctx, lifecycleOld); err != nil {
			t.Fatal(err)
		}
		if ttl, err := client.TTL(ctx, digestKey(lifecycleOld.TokenDigest)).Result(); err != nil || ttl <= 0 || ttl > 25*time.Hour {
			t.Fatalf("created session TTL must be positive and bounded: %v %v", ttl, err)
		}
		lifecycleReplacement := refreshSession("replacement-lifecycle", "attacker-family", now.Add(10*time.Minute))
		rotated, err := repo.Rotate(ctx, lifecycleOld.TokenDigest, lifecycleReplacement)
		if err != nil {
			t.Fatal(err)
		}
		if rotated.FamilyID != lifecycleOld.FamilyID || rotated.UserID != lifecycleOld.UserID {
			t.Fatalf("replacement did not inherit family/user: %#v", rotated)
		}
		if state, _ := client.HGet(ctx, digestKey(lifecycleOld.TokenDigest), "state").Result(); state != "consumed" {
			t.Fatalf("successful rotation must consume old token, state=%q", state)
		}
		if ttl, err := client.TTL(ctx, digestKey(lifecycleReplacement.TokenDigest)).Result(); err != nil || ttl <= 0 || ttl > 25*time.Hour {
			t.Fatalf("replacement TTL must be positive and bounded: %v %v", ttl, err)
		}

		old := refreshSession("old-atomic", "family-atomic", now.Add(10*time.Minute))
		if err := repo.Create(ctx, old); err != nil {
			t.Fatal(err)
		}
		var wg sync.WaitGroup
		errs := make(chan error, 8)
		success := make(chan RefreshSession, 8)
		for i := 0; i < 8; i++ {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				replacement := refreshSession(fmt.Sprintf("replacement-%d", i), "untrusted", now.Add(10*time.Minute))
				got, err := repo.Rotate(ctx, old.TokenDigest, replacement)
				if err == nil {
					success <- got
				} else {
					errs <- err
				}
			}(i)
		}
		wg.Wait()
		close(errs)
		close(success)
		var got RefreshSession
		successCount := 0
		for s := range success {
			got = s
			successCount++
		}
		if successCount != 1 {
			t.Fatalf("exactly one rotation must succeed, got %d", successCount)
		}
		if got.FamilyID != old.FamilyID || got.UserID != old.UserID {
			t.Fatalf("replacement did not inherit authority: %#v", got)
		}
		for err := range errs {
			if !errors.Is(err, ErrRefreshTokenReuse) && !errors.Is(err, ErrRefreshFamilyRevoked) {
				t.Fatalf("unexpected concurrent result: %v", err)
			}
		}
		state, _ := client.HGet(ctx, digestKey(old.TokenDigest), "state").Result()
		if state != "revoked" {
			t.Fatalf("reuse must revoke old/family sessions, state=%q", state)
		}
		if family, _ := client.HGet(ctx, digestKey(old.TokenDigest), "family_id").Result(); family != old.FamilyID {
			t.Fatal("family id changed")
		}
		if keys, _ := client.Keys(ctx, "*").Result(); len(keys) > 0 {
			for _, key := range keys {
				if key == old.FamilyID || key == "old-atomic" {
					t.Fatalf("raw token material in Redis key: %q", key)
				}
			}
		}
	})

	t.Run("expired unknown revoke user and contexts", func(t *testing.T) {
		expired := refreshSession("expired", "family-expired", now.Add(time.Minute))
		if err := repo.Create(ctx, expired); err != nil {
			t.Fatal(err)
		}
		if err := client.HSet(ctx, digestKey(expired.TokenDigest), "expires_at", now.Add(-time.Second).UnixMilli()).Err(); err != nil {
			t.Fatal(err)
		}
		_, err := repo.Rotate(ctx, expired.TokenDigest, refreshSession("expired-replacement", "ignored", now.Add(time.Minute)))
		if !errors.Is(err, ErrRefreshSessionExpired) {
			t.Fatalf("want expired, got %v", err)
		}
		if exists, _ := client.Exists(ctx, digestKey(expired.TokenDigest)).Result(); exists != 1 {
			t.Fatal("expired replay must not delete/resurrect the original session")
		}
		if exists, _ := client.Exists(ctx, digestKey(refreshDigest("expired-replacement"))).Result(); exists != 0 {
			t.Fatal("expired replay must not create a replacement")
		}
		if state, _ := client.Get(ctx, familyStateKey(expired.FamilyID)).Result(); state != "revoked" {
			t.Fatalf("expired replay must revoke family, got %q", state)
		}
		if _, err := repo.Rotate(ctx, refreshDigest("does-not-exist"), refreshSession("unknown-replacement", "x", now.Add(time.Minute))); !errors.Is(err, ErrRefreshSessionNotFound) {
			t.Fatalf("want not found, got %v", err)
		}

		userSession := refreshSession("user-session", "family-user", now.Add(5*time.Minute))
		if err := repo.Create(ctx, userSession); err != nil {
			t.Fatal(err)
		}
		if err := repo.RevokeUser(ctx, userSession.UserID); err != nil {
			t.Fatal(err)
		}
		if _, err := repo.Rotate(ctx, userSession.TokenDigest, refreshSession("user-replacement", "x", now.Add(time.Minute))); !errors.Is(err, ErrRefreshFamilyRevoked) && !errors.Is(err, ErrRefreshTokenReuse) {
			t.Fatalf("revoked user session accepted: %v", err)
		}

		cancelled, cancel := context.WithCancel(ctx)
		cancel()
		if err := repo.Create(cancelled, refreshSession("cancelled", "cancel-family", now.Add(time.Minute))); !errors.Is(err, context.Canceled) {
			t.Fatalf("cancelled context: %v", err)
		}
		deadline, stop := context.WithTimeout(ctx, time.Nanosecond)
		defer stop()
		time.Sleep(time.Millisecond)
		if _, err := repo.Rotate(deadline, refreshDigest("missing-deadline"), refreshSession("deadline-replacement", "x", now.Add(time.Minute))); !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("deadline context: %v", err)
		}
	})
}
