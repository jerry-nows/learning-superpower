package auth

import (
	"bytes"
	"testing"
	"time"
)

func TestJWTIssuerContractIssuesVerifiableSixtySecondAccessToken(t *testing.T) {
	issuedAt := time.Date(2026, time.July, 13, 9, 0, 0, 0, time.UTC)
	issuer, err := NewJWTIssuer(JWTConfig{
		SigningKey: []byte("0123456789abcdef0123456789abcdef"),
		Issuer:     "learning-superpower-local",
		Audience:   "learning-superpower-ios",
		Clock:      func() time.Time { return issuedAt },
		Random:     bytes.NewReader(make([]byte, accessTokenJTIBytes)),
	})
	if err != nil {
		t.Fatalf("new JWT issuer: %v", err)
	}

	issued, err := issuer.Issue(UserID("user-123"))
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}
	if got, want := issued.ExpiresAt.Sub(issuedAt), 60*time.Second; got != want {
		t.Fatalf("access token lifetime = %v, want %v", got, want)
	}

	claims, err := issuer.Verify(issued.Value)
	if err != nil {
		t.Fatalf("verify access token: %v", err)
	}
	if got, want := claims.UserID(), UserID("user-123"); got != want {
		t.Fatalf("verified user ID = %q, want %q", got, want)
	}
}
