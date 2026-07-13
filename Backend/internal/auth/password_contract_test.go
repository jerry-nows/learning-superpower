package auth

import (
	"errors"
	"strings"
	"testing"
)

func TestPasswordHasherCreatesUniqueOWASPArgon2idHashesThatVerify(t *testing.T) {
	t.Parallel()

	hasher := NewPasswordHasher()
	password := "correct horse battery staple"

	firstHash, err := hasher.Hash(password)
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}
	secondHash, err := hasher.Hash(password)
	if err != nil {
		t.Fatalf("hash password again: %v", err)
	}

	const expectedPrefix = "$argon2id$v=19$m=19456,t=2,p=1$"
	if !strings.HasPrefix(firstHash, expectedPrefix) {
		t.Fatalf("hash prefix = %q, want %q", firstHash, expectedPrefix)
	}
	if firstHash == secondHash {
		t.Fatal("two hashes of the same password are equal; want unique salts")
	}

	for _, encodedHash := range []string{firstHash, secondHash} {
		matches, verifyErr := hasher.Verify(password, encodedHash)
		if verifyErr != nil {
			t.Fatalf("verify password: %v", verifyErr)
		}
		if !matches {
			t.Fatal("valid password did not match its hash")
		}
	}
}

func TestPasswordHasherRejectsNonCanonicalPHCParameters(t *testing.T) {
	t.Parallel()

	hasher := NewPasswordHasher()
	encodedHash, err := hasher.Hash("correct horse battery staple")
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}
	nonCanonicalHash := strings.Replace(encodedHash, "m=19456", "m=019456", 1)

	matches, verifyErr := hasher.Verify("correct horse battery staple", nonCanonicalHash)
	if matches {
		t.Fatal("password matched a hash with non-canonical parameters")
	}
	if !errors.Is(verifyErr, ErrMalformedPasswordHash) {
		t.Fatalf("verify error = %v, want ErrMalformedPasswordHash", verifyErr)
	}
}
