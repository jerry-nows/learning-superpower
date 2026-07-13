package auth

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestRefreshTokenGeneratesCanonicalOpaqueTokenAndDigest(t *testing.T) {
	raw := bytes.Repeat([]byte{0xAB}, 32)
	token, err := NewRefreshToken(bytes.NewReader(raw))
	require.NoError(t, err)
	wantEncoded := base64.RawURLEncoding.EncodeToString(raw)
	require.Equal(t, wantEncoded, token.Encoded())
	require.Equal(t, sha256.Sum256([]byte(wantEncoded)), token.Digest())

	parsed, err := ParseRefreshToken(token.Encoded())
	require.NoError(t, err)
	require.Equal(t, token.Encoded(), parsed.Encoded())
	require.True(t, EqualRefreshTokenDigest(token.Digest(), parsed.Digest()))
}

func TestRefreshTokenRejectsShortRandomSource(t *testing.T) {
	_, err := NewRefreshToken(bytes.NewReader(make([]byte, 31)))
	require.ErrorIs(t, err, ErrRefreshTokenGeneration)
}

func TestRefreshTokenRejectsMalformedPresentedValues(t *testing.T) {
	valid := base64.RawURLEncoding.EncodeToString(make([]byte, 32))
	for _, presented := range []string{"", " " + valid, valid + "=", "%%%", base64.RawURLEncoding.EncodeToString(make([]byte, 31))} {
		_, err := ParseRefreshToken(presented)
		require.ErrorIs(t, err, ErrInvalidRefreshToken, presented)
	}
}

func TestRefreshTokenDoesNotSerializeSecrets(t *testing.T) {
	token, err := NewRefreshToken(bytes.NewReader(make([]byte, 32)))
	require.NoError(t, err)
	encoded, err := json.Marshal(token)
	require.NoError(t, err)
	require.NotContains(t, string(encoded), token.Encoded())
	require.NotContains(t, string(encoded), "digest")

	var zero RefreshToken
	_, parseErr := ParseRefreshToken("")
	require.True(t, errors.Is(parseErr, ErrInvalidRefreshToken))
	require.NotEqual(t, zero, token)
}

func TestRefreshTokenFormattingDoesNotLeakBearerValue(t *testing.T) {
	token, err := NewRefreshToken(bytes.NewReader(bytes.Repeat([]byte{0xCD}, 32)))
	require.NoError(t, err)
	formatted := fmt.Sprintf("%v %s", token, token)
	require.NotContains(t, formatted, token.Encoded())
}
