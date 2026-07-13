package auth

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"io"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	accessTokenLifetime = 60 * time.Second
	accessTokenJTIBytes = 16
	minimumHMACKeyBytes = 32
)

var (
	// ErrInvalidJWTConfig indicates that the issuer cannot be constructed safely.
	ErrInvalidJWTConfig = errors.New("invalid JWT configuration")
	// ErrAccessTokenGeneration indicates that a secure access token could not be created.
	ErrAccessTokenGeneration = errors.New("access token generation failed")
	// ErrInvalidAccessToken intentionally hides parser and signature details from callers.
	ErrInvalidAccessToken = errors.New("invalid access token")
)

// JWTConfig contains the security boundary required to issue and verify access
// tokens. SigningKey must contain at least 256 bits of secret material.
type JWTConfig struct {
	SigningKey []byte           `json:"-"`
	Issuer     string           `json:"issuer"`
	Audience   string           `json:"audience"`
	Clock      func() time.Time `json:"-"`
	Random     io.Reader        `json:"-"`
}

// IssuedAccessToken carries the encoded token and its explicit expiry so the
// auth service can populate TokenPair without parsing its own output.
type IssuedAccessToken struct {
	Value     string    `json:"-"`
	ExpiresAt time.Time `json:"-"`
}

// AccessTokenClaims are the only claims accepted at the API authorization
// boundary. Refresh tokens are opaque and never use this representation.
type AccessTokenClaims struct {
	jwt.RegisteredClaims
}

// UserID returns the authenticated user represented by the subject claim.
func (claims AccessTokenClaims) UserID() UserID {
	return UserID(claims.Subject)
}

// JWTIssuer issues and verifies HS256 access tokens for one issuer/audience.
type JWTIssuer struct {
	signingKey []byte
	issuer     string
	audience   string
	clock      func() time.Time
	random     io.Reader
}

// NewJWTIssuer validates and copies all key material before constructing an
// issuer. Defaults use the operating system CSPRNG and the system UTC clock.
func NewJWTIssuer(config JWTConfig) (*JWTIssuer, error) {
	if len(config.SigningKey) < minimumHMACKeyBytes {
		return nil, ErrInvalidJWTConfig
	}
	if config.Issuer == "" || strings.TrimSpace(config.Issuer) != config.Issuer {
		return nil, ErrInvalidJWTConfig
	}
	if config.Audience == "" || strings.TrimSpace(config.Audience) != config.Audience {
		return nil, ErrInvalidJWTConfig
	}
	clock := config.Clock
	if clock == nil {
		clock = time.Now
	}
	random := config.Random
	if random == nil {
		random = rand.Reader
	}

	return &JWTIssuer{
		signingKey: append([]byte(nil), config.SigningKey...),
		issuer:     config.Issuer,
		audience:   config.Audience,
		clock:      clock,
		random:     random,
	}, nil
}

// Issue creates an HS256 access token whose lifetime is exactly 60 seconds.
func (issuer *JWTIssuer) Issue(userID UserID) (IssuedAccessToken, error) {
	trimmedUserID := strings.TrimSpace(string(userID))
	if issuer == nil || trimmedUserID == "" || trimmedUserID != string(userID) {
		return IssuedAccessToken{}, ErrAccessTokenGeneration
	}

	issuedAt := issuer.clock().UTC().Truncate(time.Second)
	expiresAt := issuedAt.Add(accessTokenLifetime)
	jtiBytes := make([]byte, accessTokenJTIBytes)
	if _, err := io.ReadFull(issuer.random, jtiBytes); err != nil {
		return IssuedAccessToken{}, ErrAccessTokenGeneration
	}

	claims := AccessTokenClaims{RegisteredClaims: jwt.RegisteredClaims{
		Issuer:    issuer.issuer,
		Subject:   string(userID),
		Audience:  jwt.ClaimStrings{issuer.audience},
		ExpiresAt: jwt.NewNumericDate(expiresAt),
		NotBefore: jwt.NewNumericDate(issuedAt),
		IssuedAt:  jwt.NewNumericDate(issuedAt),
		ID:        base64.RawURLEncoding.EncodeToString(jtiBytes),
	}}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	encoded, err := token.SignedString(issuer.signingKey)
	if err != nil {
		return IssuedAccessToken{}, ErrAccessTokenGeneration
	}

	return IssuedAccessToken{Value: encoded, ExpiresAt: expiresAt}, nil
}

// Verify validates signature, algorithm, registered claims and the fixed
// access-token lifetime. It never returns parser details that could aid probes.
func (issuer *JWTIssuer) Verify(encoded string) (AccessTokenClaims, error) {
	if issuer == nil || encoded == "" || strings.TrimSpace(encoded) != encoded {
		return AccessTokenClaims{}, ErrInvalidAccessToken
	}

	claims := AccessTokenClaims{}
	parser := jwt.NewParser(
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(issuer.issuer),
		jwt.WithAudience(issuer.audience),
		jwt.WithExpirationRequired(),
		jwt.WithIssuedAt(),
		jwt.WithTimeFunc(func() time.Time { return issuer.clock().UTC() }),
	)
	token, err := parser.ParseWithClaims(encoded, &claims, func(token *jwt.Token) (any, error) {
		if token.Method != jwt.SigningMethodHS256 {
			return nil, ErrInvalidAccessToken
		}
		return issuer.signingKey, nil
	})
	if err != nil || token == nil || !token.Valid {
		return AccessTokenClaims{}, ErrInvalidAccessToken
	}
	if claims.Subject == "" || strings.TrimSpace(claims.Subject) != claims.Subject ||
		claims.ID == "" || claims.IssuedAt == nil ||
		claims.NotBefore == nil || claims.ExpiresAt == nil {
		return AccessTokenClaims{}, ErrInvalidAccessToken
	}
	if !claims.NotBefore.Time.Equal(claims.IssuedAt.Time) ||
		claims.ExpiresAt.Time.Sub(claims.IssuedAt.Time) != accessTokenLifetime {
		return AccessTokenClaims{}, ErrInvalidAccessToken
	}

	return claims, nil
}
