package auth

import (
	"bytes"
	"encoding/json"
	"errors"
	"reflect"
	"strings"
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

func TestJWTIssuerContractHasExactExpiryBoundaryAndRejectsFutureToken(t *testing.T) {
	issuedAt := time.Date(2026, time.July, 13, 9, 0, 0, 0, time.UTC)
	now := issuedAt
	issuer, err := NewJWTIssuer(JWTConfig{
		SigningKey: bytes.Repeat([]byte{0x42}, minimumHMACKeyBytes),
		Issuer:     "learning-superpower-local",
		Audience:   "learning-superpower-ios",
		Clock:      func() time.Time { return now },
		Random:     bytes.NewReader(make([]byte, accessTokenJTIBytes)),
	})
	if err != nil {
		t.Fatalf("new JWT issuer: %v", err)
	}

	issued, err := issuer.Issue(UserID("user-123"))
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}

	now = issuedAt.Add(59*time.Second + 999*time.Millisecond)
	if _, err := issuer.Verify(issued.Value); err != nil {
		t.Fatalf("verify immediately before expiry: %v", err)
	}
	now = issuedAt.Add(60 * time.Second)
	if _, err := issuer.Verify(issued.Value); !errors.Is(err, ErrInvalidAccessToken) {
		t.Fatalf("verify at expiry error = %v, want ErrInvalidAccessToken", err)
	}

	now = issuedAt.Add(-time.Second)
	if _, err := issuer.Verify(issued.Value); !errors.Is(err, ErrInvalidAccessToken) {
		t.Fatalf("verify before iat/nbf error = %v, want ErrInvalidAccessToken", err)
	}
}

func TestJWTConfigContractHasNoLeewayEscapeHatch(t *testing.T) {
	if _, ok := reflect.TypeFor[JWTConfig]().FieldByName("Leeway"); ok {
		t.Fatal("JWTConfig exposes Leeway, allowing access tokens beyond the exact expiry boundary")
	}
}

func TestJWTConfigContractCannotSerializeSecurityInternals(t *testing.T) {
	fakeKey := "fake-signing-key-that-must-not-serialize"
	encoded, err := json.Marshal(JWTConfig{
		SigningKey: []byte(fakeKey),
		Issuer:     "learning-superpower-local",
		Audience:   "learning-superpower-ios",
		Clock:      time.Now,
		Random:     bytes.NewReader([]byte("fake-random-source")),
	})
	if err != nil {
		t.Fatalf("marshal JWT config: %v", err)
	}

	lower := strings.ToLower(string(encoded))
	for _, forbidden := range []string{
		strings.ToLower(fakeKey),
		"signingkey",
		"clock",
		"random",
	} {
		if strings.Contains(lower, forbidden) {
			t.Fatalf("JWT config JSON contains security internal %q: %s", forbidden, encoded)
		}
	}
}
