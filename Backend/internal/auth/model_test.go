package auth

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestCredentialRecordConvertsToPublicUserWithoutPasswordHash(t *testing.T) {
	createdAt := time.Date(2026, time.July, 13, 8, 30, 0, 0, time.UTC)
	updatedAt := createdAt.Add(time.Minute)
	record := CredentialRecord{
		ID:           UserID("015f40e4-0bd1-4b45-9d79-5675300f0e11"),
		Email:        "shopper@example.com",
		Status:       UserStatusActive,
		PasswordHash: "argon2id-secret-hash",
		CreatedAt:    createdAt,
		UpdatedAt:    updatedAt,
	}

	publicUser := record.PublicUser()
	encoded, err := json.Marshal(publicUser)
	if err != nil {
		t.Fatalf("marshal public user: %v", err)
	}

	if publicUser.ID != record.ID || publicUser.Email != record.Email || publicUser.Status != record.Status {
		t.Fatalf("public identity = %#v, want values from credential record", publicUser)
	}
	if !publicUser.CreatedAt.Equal(createdAt) || !publicUser.UpdatedAt.Equal(updatedAt) {
		t.Fatalf("public timestamps = (%v, %v), want (%v, %v)", publicUser.CreatedAt, publicUser.UpdatedAt, createdAt, updatedAt)
	}
	assertJSONDoesNotContainPassword(t, encoded, record.PasswordHash)
}

func TestCredentialRecordCannotSerializePrivateFields(t *testing.T) {
	record := CredentialRecord{
		ID:           UserID("015f40e4-0bd1-4b45-9d79-5675300f0e11"),
		Email:        "shopper@example.com",
		Status:       UserStatusActive,
		PasswordHash: "argon2id-secret-hash",
		CreatedAt:    time.Date(2026, time.July, 13, 8, 30, 0, 0, time.UTC),
		UpdatedAt:    time.Date(2026, time.July, 13, 8, 31, 0, 0, time.UTC),
	}

	encoded, err := json.Marshal(record)
	if err != nil {
		t.Fatalf("marshal credential record: %v", err)
	}

	if string(encoded) != "{}" {
		t.Fatalf("credential JSON = %s, want an empty object", encoded)
	}
	assertJSONDoesNotContainPassword(t, encoded, record.PasswordHash)
}

func TestTokenPairKeepsExplicitExpiryMetadata(t *testing.T) {
	accessExpiry := time.Date(2026, time.July, 13, 8, 31, 0, 0, time.UTC)
	refreshExpiry := accessExpiry.Add(30 * 24 * time.Hour)
	pair := TokenPair{
		AccessToken:      "access-token",
		RefreshToken:     "refresh-token",
		AccessExpiresAt:  accessExpiry,
		RefreshExpiresAt: refreshExpiry,
	}

	if !pair.AccessExpiresAt.Equal(accessExpiry) || !pair.RefreshExpiresAt.Equal(refreshExpiry) {
		t.Fatalf("token expiry metadata = (%v, %v), want (%v, %v)", pair.AccessExpiresAt, pair.RefreshExpiresAt, accessExpiry, refreshExpiry)
	}
}

func TestTokenPairCannotSerializeSecretsOrMetadata(t *testing.T) {
	pair := TokenPair{
		AccessToken:      "access-token-secret",
		RefreshToken:     "refresh-token-secret",
		AccessExpiresAt:  time.Date(2026, time.July, 13, 8, 31, 0, 0, time.UTC),
		RefreshExpiresAt: time.Date(2026, time.August, 12, 8, 31, 0, 0, time.UTC),
	}

	encoded, err := json.Marshal(pair)
	if err != nil {
		t.Fatalf("marshal token pair: %v", err)
	}

	if string(encoded) != "{}" {
		t.Fatalf("token pair JSON = %s, want an empty object", encoded)
	}
	lower := strings.ToLower(string(encoded))
	for _, forbidden := range []string{
		"token",
		"password",
		"hash",
		strings.ToLower(pair.AccessToken),
		strings.ToLower(pair.RefreshToken),
	} {
		if strings.Contains(lower, forbidden) {
			t.Fatalf("token pair JSON contains forbidden material %q: %s", forbidden, encoded)
		}
	}
}

func assertJSONDoesNotContainPassword(t *testing.T, encoded []byte, hash string) {
	t.Helper()
	lower := strings.ToLower(string(encoded))
	for _, forbidden := range []string{"password", "hash", strings.ToLower(hash)} {
		if strings.Contains(lower, forbidden) {
			t.Fatalf("JSON contains forbidden credential material %q: %s", forbidden, encoded)
		}
	}
}
