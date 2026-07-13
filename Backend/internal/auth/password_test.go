package auth

import (
	"bytes"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"strings"
	"testing"

	"golang.org/x/crypto/argon2"
)

const fakeFixturePassword = "fake-test-password-not-a-secret"

func TestPasswordHasherHashAndVerify(t *testing.T) {
	hasher := NewPasswordHasher()

	encodedHash, err := hasher.Hash(fakeFixturePassword)
	if err != nil {
		t.Fatalf("Hash() error = %v", err)
	}

	matches, err := hasher.Verify(fakeFixturePassword, encodedHash)
	if err != nil {
		t.Fatalf("Verify() valid hash error = %v", err)
	}
	if !matches {
		t.Fatal("Verify() valid password = false, want true")
	}

	matches, err = hasher.Verify("fake-wrong-password", encodedHash)
	if err != nil {
		t.Fatalf("Verify() wrong password error = %v, want nil", err)
	}
	if matches {
		t.Fatal("Verify() wrong password = true, want false")
	}
}

func TestPasswordHasherHashUsesUniqueSalts(t *testing.T) {
	hasher := NewPasswordHasher()

	first, err := hasher.Hash(fakeFixturePassword)
	if err != nil {
		t.Fatalf("first Hash() error = %v", err)
	}
	second, err := hasher.Hash(fakeFixturePassword)
	if err != nil {
		t.Fatalf("second Hash() error = %v", err)
	}

	firstSalt := phcSegment(t, first, 4)
	secondSalt := phcSegment(t, second, 4)
	if firstSalt == secondSalt {
		t.Fatalf("two Hash() calls used the same salt %q", firstSalt)
	}
}

func TestPasswordHasherMatchesArgon2idInteroperabilityVector(t *testing.T) {
	// This deterministic PHC vector contains fake test fixtures only. Keeping
	// the derived key fixed guards parser/Argon2 interoperability independently
	// of Hash's random salt path.
	const encodedHash = "$argon2id$v=19$m=19456,t=2,p=1$" +
		"ZmFrZS12ZWN0b3Itc2FsdA$" +
		"n/2OmE5kPsgr1zc5Gnx1KYvN9aJY+xVIOVgqRfABe00"

	matches, err := NewPasswordHasher().Verify(fakeFixturePassword, encodedHash)
	if err != nil {
		t.Fatalf("Verify() interoperability vector error = %v", err)
	}
	if !matches {
		t.Fatal("Verify() interoperability vector = false, want true")
	}
}

func TestPasswordHasherRejectsMalformedPHC(t *testing.T) {
	validHash := deterministicPasswordHash(t)
	parts := strings.Split(validHash, "$")
	validSalt := parts[4]
	validKey := parts[5]
	raw := func(size int) string {
		return base64.RawStdEncoding.EncodeToString(bytes.Repeat([]byte{0x5a}, size))
	}

	tests := []struct {
		name        string
		encodedHash string
	}{
		{name: "empty", encodedHash: ""},
		{name: "missing leading delimiter", encodedHash: strings.TrimPrefix(validHash, "$")},
		{name: "missing key segment", encodedHash: strings.TrimSuffix(validHash, "$"+validKey)},
		{name: "extra segment", encodedHash: validHash + "$extra"},
		{name: "wrong algorithm", encodedHash: strings.Replace(validHash, "$argon2id$", "$argon2i$", 1)},
		{name: "algorithm is case sensitive", encodedHash: strings.Replace(validHash, "$argon2id$", "$Argon2id$", 1)},
		{name: "wrong version", encodedHash: strings.Replace(validHash, "$v=19$", "$v=16$", 1)},
		{name: "missing version", encodedHash: strings.Replace(validHash, "$v=19$", "$$", 1)},
		{name: "parameter order", encodedHash: replacePHCParameters(validHash, "t=2,m=19456,p=1")},
		{name: "duplicate memory", encodedHash: replacePHCParameters(validHash, "m=19456,m=19456,p=1")},
		{name: "missing memory", encodedHash: replacePHCParameters(validHash, "t=2,p=1")},
		{name: "missing time", encodedHash: replacePHCParameters(validHash, "m=19456,p=1")},
		{name: "missing parallelism", encodedHash: replacePHCParameters(validHash, "m=19456,t=2")},
		{name: "extra parameter", encodedHash: replacePHCParameters(validHash, "m=19456,t=2,p=1,x=1")},
		{name: "empty memory", encodedHash: replacePHCParameters(validHash, "m=,t=2,p=1")},
		{name: "nonnumeric memory", encodedHash: replacePHCParameters(validHash, "m=lots,t=2,p=1")},
		{name: "positive sign", encodedHash: replacePHCParameters(validHash, "m=+19456,t=2,p=1")},
		{name: "negative sign", encodedHash: replacePHCParameters(validHash, "m=-19456,t=2,p=1")},
		{name: "leading zero", encodedHash: replacePHCParameters(validHash, "m=019456,t=2,p=1")},
		{name: "memory uint32 overflow", encodedHash: replacePHCParameters(validHash, "m=4294967296,t=2,p=1")},
		{name: "threads uint8 overflow", encodedHash: replacePHCParameters(validHash, "m=19456,t=2,p=256")},
		{name: "memory below minimum", encodedHash: replacePHCParameters(validHash, "m=19455,t=2,p=1")},
		{name: "memory above cap", encodedHash: replacePHCParameters(validHash, "m=262145,t=2,p=1")},
		{name: "time below minimum", encodedHash: replacePHCParameters(validHash, "m=19456,t=1,p=1")},
		{name: "time above cap", encodedHash: replacePHCParameters(validHash, "m=19456,t=11,p=1")},
		{name: "parallelism below minimum", encodedHash: replacePHCParameters(validHash, "m=19456,t=2,p=0")},
		{name: "parallelism above cap", encodedHash: replacePHCParameters(validHash, "m=19456,t=2,p=9")},
		{name: "salt too short", encodedHash: replacePHCSegment(validHash, 4, raw(defaultSaltBytes-1))},
		{name: "salt too long", encodedHash: replacePHCSegment(validHash, 4, raw(maxSaltBytes+1))},
		{name: "key too short", encodedHash: replacePHCSegment(validHash, 5, raw(int(passwordKeyBytes)-1))},
		{name: "key too long", encodedHash: replacePHCSegment(validHash, 5, raw(int(passwordKeyBytes)+1))},
		{name: "salt invalid alphabet", encodedHash: replacePHCSegment(validHash, 4, strings.Repeat("!", len(validSalt)))},
		{name: "key invalid alphabet", encodedHash: replacePHCSegment(validHash, 5, strings.Repeat("!", len(validKey)))},
		{name: "salt padding", encodedHash: replacePHCSegment(validHash, 4, validSalt+"==")},
		{name: "key padding", encodedHash: replacePHCSegment(validHash, 5, validKey+"=")},
		{name: "salt space", encodedHash: replacePHCSegment(validHash, 4, validSalt[:1]+" "+validSalt[2:])},
		{name: "key tab", encodedHash: replacePHCSegment(validHash, 5, validKey[:1]+"\t"+validKey[2:])},
		{name: "salt line feed", encodedHash: replacePHCSegment(validHash, 4, validSalt[:1]+"\n"+validSalt[1:])},
		{name: "key carriage return", encodedHash: replacePHCSegment(validHash, 5, validKey[:1]+"\r"+validKey[1:])},
		{name: "salt noncanonical trailing bits", encodedHash: replacePHCSegment(validHash, 4, strings.TrimSuffix(raw(defaultSaltBytes), "g")+"h")},
		{name: "key noncanonical trailing bits", encodedHash: replacePHCSegment(validHash, 5, strings.TrimSuffix(raw(int(passwordKeyBytes)), "o")+"p")},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			matches, err := NewPasswordHasher().Verify(fakeFixturePassword, test.encodedHash)
			if matches {
				t.Fatal("Verify() malformed hash = true, want false")
			}
			if !errors.Is(err, ErrMalformedPasswordHash) {
				t.Fatalf("Verify() error = %v, want ErrMalformedPasswordHash", err)
			}
		})
	}
}

func TestPasswordHasherRejectsExtremeCostsBeforeKeyDerivation(t *testing.T) {
	validHash := deterministicPasswordHash(t)
	tests := []string{
		"m=4294967295,t=2,p=1",
		"m=19456,t=4294967295,p=1",
		"m=19456,t=2,p=255",
	}

	for _, parameters := range tests {
		t.Run(parameters, func(t *testing.T) {
			matches, err := NewPasswordHasher().Verify(
				fakeFixturePassword,
				replacePHCParameters(validHash, parameters),
			)
			if matches || !errors.Is(err, ErrMalformedPasswordHash) {
				t.Fatalf("Verify() = (%v, %v), want (false, ErrMalformedPasswordHash)", matches, err)
			}
		})
	}
}

func TestPasswordHasherHashRejectsUninitializedHasher(t *testing.T) {
	tests := []struct {
		name   string
		hasher *PasswordHasher
	}{
		{name: "nil receiver", hasher: nil},
		{name: "zero value", hasher: &PasswordHasher{}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			encodedHash, err := test.hasher.Hash(fakeFixturePassword)
			if err == nil {
				t.Fatalf("Hash() = %q with nil error, want initialization error", encodedHash)
			}
			if encodedHash != "" {
				t.Fatalf("Hash() = %q, want empty hash on error", encodedHash)
			}
		})
	}
}

func TestPasswordHasherHashPropagatesRandomSourceFailure(t *testing.T) {
	sentinel := errors.New("fake random source failure")
	tests := []struct {
		name   string
		reader io.Reader
	}{
		{name: "reader error", reader: errorReader{err: sentinel}},
		{name: "short random input", reader: bytes.NewReader(make([]byte, defaultSaltBytes-1))},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			hasher := &PasswordHasher{random: test.reader}
			encodedHash, err := hasher.Hash(fakeFixturePassword)
			if err == nil {
				t.Fatalf("Hash() = %q with nil error, want random source error", encodedHash)
			}
			if encodedHash != "" {
				t.Fatalf("Hash() = %q, want empty hash on error", encodedHash)
			}
			if test.name == "reader error" && !errors.Is(err, sentinel) {
				t.Fatalf("Hash() error = %v, want wrapped sentinel error", err)
			}
		})
	}
}

type errorReader struct {
	err error
}

func (reader errorReader) Read([]byte) (int, error) {
	return 0, reader.err
}

func deterministicPasswordHash(t *testing.T) string {
	t.Helper()
	salt := []byte("fake-fixture-salt")
	key := argon2.IDKey(
		[]byte(fakeFixturePassword),
		salt,
		defaultTime,
		defaultMemoryKiB,
		defaultThreads,
		passwordKeyBytes,
	)
	defer clear(key)
	return fmt.Sprintf(
		"$argon2id$v=19$m=19456,t=2,p=1$%s$%s",
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key),
	)
}

func phcSegment(t *testing.T, encodedHash string, index int) string {
	t.Helper()
	parts := strings.Split(encodedHash, "$")
	if len(parts) != 6 {
		t.Fatalf("PHC segment count = %d, want 6", len(parts))
	}
	return parts[index]
}

func replacePHCParameters(encodedHash, parameters string) string {
	return replacePHCSegment(encodedHash, 3, parameters)
}

func replacePHCSegment(encodedHash string, index int, replacement string) string {
	parts := strings.Split(encodedHash, "$")
	parts[index] = replacement
	return strings.Join(parts, "$")
}
