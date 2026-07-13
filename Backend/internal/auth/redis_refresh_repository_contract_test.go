package auth

import (
	"crypto/sha256"
	"strings"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
)

func TestRedisRefreshRepositoryContract(t *testing.T) {
	if _, err := NewRedisRefreshRepository((*redis.Client)(nil), time.Second); err == nil {
		t.Fatal("nil redis client must be rejected")
	}
	var d [sha256.Size]byte
	d[0] = 42
	key := digestKey(d)
	if !strings.HasPrefix(key, "auth:refresh:session:") || strings.Contains(key, "*") || strings.Contains(key, "token") {
		t.Fatalf("unsafe digest key: %q", key)
	}
	s := RefreshSession{FamilyID: "family", UserID: "user", TokenDigest: d, ExpiresAt: time.Now().Add(time.Minute)}
	if !validSession(s, time.Now()) {
		t.Fatal("valid session rejected")
	}
	for _, marker := range []string{"EXISTS',k", "PEXPIRE", "return 2"} {
		if !strings.Contains(createLua, marker) {
			t.Fatalf("create script missing collision/ttl marker %q", marker)
		}
	}
	for _, marker := range []string{"EXISTS', nk", "return {5}", "PEXPIRE', famset"} {
		if !strings.Contains(rotateLua, marker) {
			t.Fatalf("rotate script missing collision/ttl marker %q", marker)
		}
	}
	if !strings.Contains(rotateLua, "auth:refresh:user:' .. user") {
		t.Fatal("rotate script must retain authoritative user index")
	}
}
