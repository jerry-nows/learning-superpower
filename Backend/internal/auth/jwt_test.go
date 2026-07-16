package auth

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	testJWTIssuer   = "learning-superpower-local"
	testJWTAudience = "learning-superpower-ios"
)

var (
	testJWTNow = time.Date(2026, time.July, 13, 9, 10, 11, 987654321, time.UTC)
	testJWTKey = bytes.Repeat([]byte{0x5a}, minimumHMACKeyBytes)
)

func TestJWTIssuerIssuesExactClaimsAndExpiry(t *testing.T) {
	t.Parallel()

	issuer := mustNewTestJWTIssuer(t, testJWTNow, bytes.NewReader(bytes.Repeat([]byte{0x2a}, accessTokenJTIBytes)))
	issued, err := issuer.Issue(UserID("user-123"))
	if err != nil {
		t.Fatalf("Issue() error = %v", err)
	}

	wantIssuedAt := testJWTNow.Truncate(time.Second)
	if got, want := issued.ExpiresAt, wantIssuedAt.Add(60*time.Second); !got.Equal(want) {
		t.Fatalf("ExpiresAt = %v, want %v", got, want)
	}

	claims, err := issuer.Verify(issued.Value)
	if err != nil {
		t.Fatalf("Verify() error = %v", err)
	}
	if got, want := claims.Issuer, testJWTIssuer; got != want {
		t.Errorf("issuer = %q, want %q", got, want)
	}
	if got, want := claims.UserID(), UserID("user-123"); got != want {
		t.Errorf("user ID = %q, want %q", got, want)
	}
	if len(claims.Audience) != 1 || claims.Audience[0] != testJWTAudience {
		t.Errorf("audience = %v, want only %q", claims.Audience, testJWTAudience)
	}
	if claims.IssuedAt == nil || !claims.IssuedAt.Time.Equal(wantIssuedAt) {
		t.Errorf("iat = %v, want %v", claims.IssuedAt, wantIssuedAt)
	}
	if claims.NotBefore == nil || !claims.NotBefore.Time.Equal(wantIssuedAt) {
		t.Errorf("nbf = %v, want %v", claims.NotBefore, wantIssuedAt)
	}
	if claims.ExpiresAt == nil || !claims.ExpiresAt.Time.Equal(issued.ExpiresAt) {
		t.Errorf("exp = %v, want %v", claims.ExpiresAt, issued.ExpiresAt)
	}
}

func TestJWTIssuerExpiryHasNoLeeway(t *testing.T) {
	t.Parallel()

	issuedAt := testJWTNow.Truncate(time.Second)
	now := issuedAt
	issuer := mustNewTestJWTIssuerWithClock(t, func() time.Time { return now }, bytes.NewReader(make([]byte, accessTokenJTIBytes)))
	issued, err := issuer.Issue(UserID("user-123"))
	if err != nil {
		t.Fatalf("Issue() error = %v", err)
	}

	for _, test := range []struct {
		name    string
		now     time.Time
		wantErr bool
	}{
		{name: "before expiry", now: issuedAt.Add(59*time.Second + 999*time.Millisecond)},
		{name: "at expiry", now: issuedAt.Add(60 * time.Second), wantErr: true},
		{name: "after expiry", now: issuedAt.Add(61 * time.Second), wantErr: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			now = test.now
			_, verifyErr := issuer.Verify(issued.Value)
			if test.wantErr {
				assertInvalidAccessToken(t, verifyErr)
			} else if verifyErr != nil {
				t.Fatalf("Verify() error = %v", verifyErr)
			}
		})
	}
}

func TestJWTIssuerRejectsInvalidSignaturesAndAlgorithms(t *testing.T) {
	t.Parallel()

	issuer := mustNewTestJWTIssuer(t, testJWTNow, bytes.NewReader(make([]byte, accessTokenJTIBytes)))
	valid, err := issuer.Issue(UserID("user-123"))
	if err != nil {
		t.Fatalf("Issue() error = %v", err)
	}
	claims := validTestClaims(testJWTNow.Truncate(time.Second))

	tampered := tamperJWTSignature(t, valid.Value)
	wrongKey := signTestClaims(t, jwt.SigningMethodHS256, bytes.Repeat([]byte{0x7b}, minimumHMACKeyBytes), claims)
	hs384 := signTestClaims(t, jwt.SigningMethodHS384, testJWTKey, claims)
	none := signTestClaims(t, jwt.SigningMethodNone, jwt.UnsafeAllowNoneSignatureType, claims)

	for _, test := range []struct {
		name  string
		token string
	}{
		{name: "tampered signature", token: tampered},
		{name: "wrong key", token: wrongKey},
		{name: "HS384 method confusion", token: hs384},
		{name: "none algorithm", token: none},
	} {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			_, verifyErr := issuer.Verify(test.token)
			assertInvalidAccessToken(t, verifyErr)
		})
	}
}

func TestJWTIssuerRejectsInvalidRegisteredClaims(t *testing.T) {
	t.Parallel()

	now := testJWTNow.Truncate(time.Second)
	issuer := mustNewTestJWTIssuer(t, now, bytes.NewReader(make([]byte, accessTokenJTIBytes)))
	valid := validTestClaims(now)

	tests := []struct {
		name   string
		mutate func(*jwt.RegisteredClaims)
	}{
		{name: "issuer mismatch", mutate: func(c *jwt.RegisteredClaims) { c.Issuer = "other-issuer" }},
		{name: "audience mismatch", mutate: func(c *jwt.RegisteredClaims) { c.Audience = jwt.ClaimStrings{"other-audience"} }},
		{name: "missing subject", mutate: func(c *jwt.RegisteredClaims) { c.Subject = "" }},
		{name: "whitespace subject", mutate: func(c *jwt.RegisteredClaims) { c.Subject = " user-123 " }},
		{name: "missing JTI", mutate: func(c *jwt.RegisteredClaims) { c.ID = "" }},
		{name: "missing iat", mutate: func(c *jwt.RegisteredClaims) { c.IssuedAt = nil }},
		{name: "missing nbf", mutate: func(c *jwt.RegisteredClaims) { c.NotBefore = nil }},
		{name: "missing exp", mutate: func(c *jwt.RegisteredClaims) { c.ExpiresAt = nil }},
		{name: "altered lifetime", mutate: func(c *jwt.RegisteredClaims) { c.ExpiresAt = jwt.NewNumericDate(now.Add(61 * time.Second)) }},
		{name: "nbf differs from iat", mutate: func(c *jwt.RegisteredClaims) { c.NotBefore = jwt.NewNumericDate(now.Add(-time.Second)) }},
		{name: "future iat", mutate: func(c *jwt.RegisteredClaims) {
			c.IssuedAt = jwt.NewNumericDate(now.Add(time.Second))
			c.NotBefore = jwt.NewNumericDate(now.Add(time.Second))
			c.ExpiresAt = jwt.NewNumericDate(now.Add(61 * time.Second))
		}},
		{name: "future nbf", mutate: func(c *jwt.RegisteredClaims) { c.NotBefore = jwt.NewNumericDate(now.Add(time.Second)) }},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			claims := valid
			test.mutate(&claims)
			encoded := signTestClaims(t, jwt.SigningMethodHS256, testJWTKey, claims)
			_, verifyErr := issuer.Verify(encoded)
			assertInvalidAccessToken(t, verifyErr)
		})
	}
}

func TestJWTIssuerRejectsMalformedAndNoncanonicalTokens(t *testing.T) {
	t.Parallel()

	issuer := mustNewTestJWTIssuer(t, testJWTNow, bytes.NewReader(make([]byte, accessTokenJTIBytes)))
	issued, err := issuer.Issue(UserID("user-123"))
	if err != nil {
		t.Fatalf("Issue() error = %v", err)
	}

	for _, encoded := range []string{"", "not-a-jwt", "a.b", "a.b.c.d", " " + issued.Value, issued.Value + "\n"} {
		_, verifyErr := issuer.Verify(encoded)
		assertInvalidAccessToken(t, verifyErr)
	}
	var nilIssuer *JWTIssuer
	_, verifyErr := nilIssuer.Verify(issued.Value)
	assertInvalidAccessToken(t, verifyErr)
}

func TestNewJWTIssuerValidatesConfiguration(t *testing.T) {
	t.Parallel()

	valid := JWTConfig{SigningKey: testJWTKey, Issuer: testJWTIssuer, Audience: testJWTAudience}
	tests := []struct {
		name   string
		mutate func(*JWTConfig)
	}{
		{name: "short key", mutate: func(c *JWTConfig) { c.SigningKey = bytes.Repeat([]byte{1}, minimumHMACKeyBytes-1) }},
		{name: "empty issuer", mutate: func(c *JWTConfig) { c.Issuer = "" }},
		{name: "leading issuer whitespace", mutate: func(c *JWTConfig) { c.Issuer = " " + c.Issuer }},
		{name: "trailing issuer whitespace", mutate: func(c *JWTConfig) { c.Issuer += " " }},
		{name: "empty audience", mutate: func(c *JWTConfig) { c.Audience = "" }},
		{name: "leading audience whitespace", mutate: func(c *JWTConfig) { c.Audience = " " + c.Audience }},
		{name: "trailing audience whitespace", mutate: func(c *JWTConfig) { c.Audience += " " }},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			config := valid
			test.mutate(&config)
			issuer, err := NewJWTIssuer(config)
			if issuer != nil || !errors.Is(err, ErrInvalidJWTConfig) || err != ErrInvalidJWTConfig {
				t.Fatalf("NewJWTIssuer() = (%v, %v), want (nil, ErrInvalidJWTConfig)", issuer, err)
			}
		})
	}
}

func TestJWTIssuerCopiesSigningKey(t *testing.T) {
	t.Parallel()

	key := append([]byte(nil), testJWTKey...)
	issuer, err := NewJWTIssuer(JWTConfig{
		SigningKey: key,
		Issuer:     testJWTIssuer,
		Audience:   testJWTAudience,
		Clock:      func() time.Time { return testJWTNow },
		Random:     bytes.NewReader(make([]byte, accessTokenJTIBytes)),
	})
	if err != nil {
		t.Fatalf("NewJWTIssuer() error = %v", err)
	}
	for index := range key {
		key[index] ^= 0xff
	}
	issued, err := issuer.Issue(UserID("user-123"))
	if err != nil {
		t.Fatalf("Issue() error after caller key mutation = %v", err)
	}
	if _, err := issuer.Verify(issued.Value); err != nil {
		t.Fatalf("Verify() error after caller key mutation = %v", err)
	}
}

func TestJWTIssuerUsesUniqueFixedEntropyJTIs(t *testing.T) {
	t.Parallel()

	random := append(bytes.Repeat([]byte{0x11}, accessTokenJTIBytes), bytes.Repeat([]byte{0x22}, accessTokenJTIBytes)...)
	issuer := mustNewTestJWTIssuer(t, testJWTNow, bytes.NewReader(random))

	first, err := issuer.Issue(UserID("user-123"))
	if err != nil {
		t.Fatalf("first Issue() error = %v", err)
	}
	second, err := issuer.Issue(UserID("user-123"))
	if err != nil {
		t.Fatalf("second Issue() error = %v", err)
	}
	firstClaims, err := issuer.Verify(first.Value)
	if err != nil {
		t.Fatalf("verify first token: %v", err)
	}
	secondClaims, err := issuer.Verify(second.Value)
	if err != nil {
		t.Fatalf("verify second token: %v", err)
	}
	if firstClaims.ID == secondClaims.ID {
		t.Fatal("sequential tokens reused a JTI")
	}
	for _, id := range []string{firstClaims.ID, secondClaims.ID} {
		decoded, decodeErr := base64.RawURLEncoding.DecodeString(id)
		if decodeErr != nil {
			t.Fatalf("JTI %q is not raw base64url: %v", id, decodeErr)
		}
		if got, want := len(decoded), accessTokenJTIBytes; got != want {
			t.Fatalf("JTI entropy bytes = %d, want %d", got, want)
		}
		if strings.ContainsAny(id, "+/=") {
			t.Fatalf("JTI %q is not unpadded URL-safe base64", id)
		}
	}
}

func TestJWTIssuerCollapsesRandomFailures(t *testing.T) {
	t.Parallel()

	secretFailure := errors.New("entropy source /private/path failed")
	for _, test := range []struct {
		name   string
		reader io.Reader
	}{
		{name: "reader error", reader: failingJWTReader{err: secretFailure}},
		{name: "short read", reader: bytes.NewReader(make([]byte, accessTokenJTIBytes-1))},
	} {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			issuer := mustNewTestJWTIssuer(t, testJWTNow, test.reader)
			issued, err := issuer.Issue(UserID("user-123"))
			if issued != (IssuedAccessToken{}) {
				t.Fatalf("Issue() token = %#v, want zero value", issued)
			}
			if err != ErrAccessTokenGeneration || !errors.Is(err, ErrAccessTokenGeneration) {
				t.Fatalf("Issue() error = %v, want ErrAccessTokenGeneration", err)
			}
			if errors.Is(err, secretFailure) || strings.Contains(err.Error(), secretFailure.Error()) {
				t.Fatalf("Issue() leaked entropy failure detail: %v", err)
			}
		})
	}
}

func TestJWTIssuerRejectsInvalidUserIDsWithoutDetails(t *testing.T) {
	t.Parallel()

	for _, userID := range []UserID{"", " ", " user-123", "user-123 "} {
		issuer := mustNewTestJWTIssuer(t, testJWTNow, bytes.NewReader(make([]byte, accessTokenJTIBytes)))
		issued, err := issuer.Issue(userID)
		if issued != (IssuedAccessToken{}) || err != ErrAccessTokenGeneration {
			t.Fatalf("Issue(%q) = (%#v, %v), want zero token and ErrAccessTokenGeneration", userID, issued, err)
		}
	}
	var nilIssuer *JWTIssuer
	if _, err := nilIssuer.Issue(UserID("user-123")); err != ErrAccessTokenGeneration {
		t.Fatalf("nil issuer Issue() error = %v, want ErrAccessTokenGeneration", err)
	}
}

func TestJWTIssuerErrorsCollapseAndPreserveSentinelSemantics(t *testing.T) {
	t.Parallel()

	issuer := mustNewTestJWTIssuer(t, testJWTNow, bytes.NewReader(make([]byte, accessTokenJTIBytes)))
	_, err := issuer.Verify("header.payload.signature")
	if err != ErrInvalidAccessToken || !errors.Is(err, ErrInvalidAccessToken) {
		t.Fatalf("Verify() error = %v, want exact ErrInvalidAccessToken", err)
	}
	for _, leaked := range []string{"signature", "token is", "malformed", "base64", "parse"} {
		if strings.Contains(strings.ToLower(err.Error()), leaked) {
			t.Fatalf("Verify() leaked parser detail %q: %v", leaked, err)
		}
	}
	if errors.Is(err, jwt.ErrTokenMalformed) {
		t.Fatalf("Verify() error exposes parser error through errors.Is: %v", err)
	}
}

func TestJWTTypesDoNotSerializeSecrets(t *testing.T) {
	t.Parallel()

	configJSON, err := json.Marshal(JWTConfig{
		SigningKey: []byte("fake-secret-signing-key-material"),
		Issuer:     testJWTIssuer,
		Audience:   testJWTAudience,
		Clock:      time.Now,
		Random:     strings.NewReader("fake-secret-random-material"),
	})
	if err != nil {
		t.Fatalf("marshal JWTConfig: %v", err)
	}
	if got, want := string(configJSON), `{"issuer":"learning-superpower-local","audience":"learning-superpower-ios"}`; got != want {
		t.Fatalf("JWTConfig JSON = %s, want %s", got, want)
	}

	issuedJSON, err := json.Marshal(IssuedAccessToken{Value: "fake.secret.token", ExpiresAt: testJWTNow})
	if err != nil {
		t.Fatalf("marshal IssuedAccessToken: %v", err)
	}
	if got, want := string(issuedJSON), `{}`; got != want {
		t.Fatalf("IssuedAccessToken JSON = %s, want %s", got, want)
	}
}

func mustNewTestJWTIssuer(t *testing.T, now time.Time, random io.Reader) *JWTIssuer {
	t.Helper()
	return mustNewTestJWTIssuerWithClock(t, func() time.Time { return now }, random)
}

func mustNewTestJWTIssuerWithClock(t *testing.T, clock func() time.Time, random io.Reader) *JWTIssuer {
	t.Helper()
	issuer, err := NewJWTIssuer(JWTConfig{
		SigningKey: testJWTKey,
		Issuer:     testJWTIssuer,
		Audience:   testJWTAudience,
		Clock:      clock,
		Random:     random,
	})
	if err != nil {
		t.Fatalf("NewJWTIssuer() error = %v", err)
	}
	return issuer
}

func validTestClaims(now time.Time) jwt.RegisteredClaims {
	return jwt.RegisteredClaims{
		Issuer:    testJWTIssuer,
		Subject:   "user-123",
		Audience:  jwt.ClaimStrings{testJWTAudience},
		ExpiresAt: jwt.NewNumericDate(now.Add(accessTokenLifetime)),
		NotBefore: jwt.NewNumericDate(now),
		IssuedAt:  jwt.NewNumericDate(now),
		ID:        "valid-test-jti",
	}
}

func signTestClaims(t *testing.T, method jwt.SigningMethod, key any, claims jwt.RegisteredClaims) string {
	t.Helper()
	encoded, err := jwt.NewWithClaims(method, AccessTokenClaims{RegisteredClaims: claims}).SignedString(key)
	if err != nil {
		t.Fatalf("sign deliberately constructed test token: %v", err)
	}
	return encoded
}

func tamperJWTSignature(t *testing.T, encoded string) string {
	t.Helper()
	signatureStart := strings.LastIndexByte(encoded, '.') + 1
	if signatureStart <= 0 || signatureStart >= len(encoded) {
		t.Fatalf("test token has no signature segment: %q", encoded)
	}
	tampered := []byte(encoded)
	if tampered[signatureStart] == 'A' {
		tampered[signatureStart] = 'B'
	} else {
		tampered[signatureStart] = 'A'
	}
	return string(tampered)
}

func assertInvalidAccessToken(t *testing.T, err error) {
	t.Helper()
	if err != ErrInvalidAccessToken || !errors.Is(err, ErrInvalidAccessToken) {
		t.Fatalf("error = %v, want exact ErrInvalidAccessToken", err)
	}
}

type failingJWTReader struct {
	err error
}

func (reader failingJWTReader) Read(_ []byte) (int, error) {
	return 0, fmt.Errorf("read random: %w", reader.err)
}
