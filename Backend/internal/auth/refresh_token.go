package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"strings"
)

const refreshTokenRawBytes = 32

var (
	ErrRefreshTokenGeneration = errors.New("refresh token generation failed")
	ErrInvalidRefreshToken    = errors.New("invalid refresh token")
)

// RefreshToken keeps the presented opaque value and its storage-only digest
// private. Callers must use explicit accessors when mapping either boundary.
type RefreshToken struct {
	encoded string
	digest  [sha256.Size]byte
}

// NewRefreshToken creates a cryptographically random 256-bit token. A nil
// reader selects the operating-system CSPRNG; injected readers are intended
// only for deterministic tests and must still provide all 32 bytes.
func NewRefreshToken(random io.Reader) (RefreshToken, error) {
	if random == nil {
		random = rand.Reader
	}
	raw := make([]byte, refreshTokenRawBytes)
	if _, err := io.ReadFull(random, raw); err != nil {
		return RefreshToken{}, ErrRefreshTokenGeneration
	}
	return newRefreshToken(raw), nil
}

// GenerateRefreshToken is a descriptive alias for NewRefreshToken.
func GenerateRefreshToken(random io.Reader) (RefreshToken, error) {
	return NewRefreshToken(random)
}

func newRefreshToken(raw []byte) RefreshToken {
	encoded := base64.RawURLEncoding.EncodeToString(raw)
	return RefreshToken{encoded: encoded, digest: sha256.Sum256([]byte(encoded))}
}

// ParseRefreshToken validates the exact canonical transport representation.
// The storage digest is always computed over the encoded value, never decoded
// bytes, so repository comparisons cannot accidentally mix representations.
func ParseRefreshToken(presented string) (RefreshToken, error) {
	if presented == "" || strings.TrimSpace(presented) != presented {
		return RefreshToken{}, ErrInvalidRefreshToken
	}
	raw, err := base64.RawURLEncoding.DecodeString(presented)
	if err != nil || len(raw) != refreshTokenRawBytes || base64.RawURLEncoding.EncodeToString(raw) != presented {
		return RefreshToken{}, ErrInvalidRefreshToken
	}
	return newRefreshToken(raw), nil
}

// Encoded returns the exact opaque value suitable for an HTTP response or
// request. It is deliberately not a JSON field.
func (token RefreshToken) Encoded() string { return token.encoded }

// MarshalJSON intentionally emits no fields. Refresh tokens must only cross
// the transport boundary through an explicit response DTO.
func (token RefreshToken) MarshalJSON() ([]byte, error) { return []byte("{}"), nil }

// Format prevents the default formatter from exposing unexported bearer and
// digest fields in logs. Transport code must call Encoded explicitly.
func (token RefreshToken) Format(state fmt.State, verb rune) {
	_, _ = io.WriteString(state, "[redacted refresh token]")
}

// Digest returns the SHA-256 storage digest. The fixed-size value prevents
// callers from mutating the token's internal state.
func (token RefreshToken) Digest() [sha256.Size]byte { return token.digest }

// EqualRefreshTokenDigest compares digests in constant time.
func EqualRefreshTokenDigest(left, right [sha256.Size]byte) bool {
	return subtle.ConstantTimeCompare(left[:], right[:]) == 1
}
