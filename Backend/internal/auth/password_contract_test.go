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

func TestPasswordHasherRejectsLineBreaksInPHCBase64Segments(t *testing.T) {
	t.Parallel()

	hasher := NewPasswordHasher()
	encodedHash, err := hasher.Hash("correct horse battery staple")
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}
	parts := strings.Split(encodedHash, "$")
	if len(parts) != 6 {
		t.Fatalf("generated PHC parts = %d, want 6", len(parts))
	}

	tests := []struct {
		name    string
		segment int
		lineEnd string
	}{
		{name: "salt LF", segment: 4, lineEnd: "\n"},
		{name: "salt CR", segment: 4, lineEnd: "\r"},
		{name: "key LF", segment: 5, lineEnd: "\n"},
		{name: "key CR", segment: 5, lineEnd: "\r"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			malformedParts := append([]string(nil), parts...)
			malformedParts[test.segment] = malformedParts[test.segment][:1] + test.lineEnd + malformedParts[test.segment][1:]

			matches, verifyErr := hasher.Verify("correct horse battery staple", strings.Join(malformedParts, "$"))
			if matches {
				t.Fatal("password matched a PHC value containing a line break")
			}
			if !errors.Is(verifyErr, ErrMalformedPasswordHash) {
				t.Fatalf("verify error = %v, want ErrMalformedPasswordHash", verifyErr)
			}
		})
	}
}
