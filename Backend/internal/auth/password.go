package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"

	"golang.org/x/crypto/argon2"
)

const (
	argon2Version = 19

	defaultMemoryKiB uint32 = 19_456
	defaultTime      uint32 = 2
	defaultThreads   uint8  = 1
	defaultSaltBytes        = 16
	passwordKeyBytes uint32 = 32

	maxMemoryKiB uint32 = 262_144
	maxTime      uint32 = 10
	maxThreads   uint8  = 8
	maxSaltBytes        = 64
)

// ErrMalformedPasswordHash distinguishes an invalid stored representation
// from an ordinary password mismatch.
var ErrMalformedPasswordHash = errors.New("malformed password hash")

// PasswordHasher hashes and verifies passwords with the OWASP minimum
// Argon2id work factors. Its zero value is not intended for use; construct it
// with NewPasswordHasher.
type PasswordHasher struct {
	random io.Reader
}

// NewPasswordHasher returns a production password hasher backed by the
// operating system's cryptographically secure random source.
func NewPasswordHasher() *PasswordHasher {
	return &PasswordHasher{random: rand.Reader}
}

// Hash derives a salted Argon2id key and returns its standard PHC encoding.
func (hasher *PasswordHasher) Hash(password string) (string, error) {
	if hasher == nil || hasher.random == nil {
		return "", errors.New("password hasher is not initialized")
	}

	salt := make([]byte, defaultSaltBytes)
	if _, err := io.ReadFull(hasher.random, salt); err != nil {
		return "", fmt.Errorf("generate password salt: %w", err)
	}

	passwordBytes := []byte(password)
	key := argon2.IDKey(passwordBytes, salt, defaultTime, defaultMemoryKiB, defaultThreads, passwordKeyBytes)
	clear(passwordBytes)

	encoded := fmt.Sprintf(
		"$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2Version,
		defaultMemoryKiB,
		defaultTime,
		defaultThreads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key),
	)
	clear(key)

	return encoded, nil
}

// Verify compares a password with a PHC-encoded Argon2id hash. A password
// mismatch returns false with no error; malformed or unsafe encodings return
// ErrMalformedPasswordHash without running attacker-controlled excessive work.
func (hasher *PasswordHasher) Verify(password, encodedHash string) (bool, error) {
	params, salt, expectedKey, err := parsePasswordHash(encodedHash)
	if err != nil {
		return false, err
	}

	passwordBytes := []byte(password)
	actualKey := argon2.IDKey(passwordBytes, salt, params.time, params.memoryKiB, params.threads, passwordKeyBytes)
	clear(passwordBytes)
	defer clear(actualKey)
	defer clear(expectedKey)

	return subtle.ConstantTimeCompare(actualKey, expectedKey) == 1, nil
}

type argon2Parameters struct {
	memoryKiB uint32
	time      uint32
	threads   uint8
}

func parsePasswordHash(encodedHash string) (argon2Parameters, []byte, []byte, error) {
	parts := strings.Split(encodedHash, "$")
	if len(parts) != 6 || parts[0] != "" || parts[1] != "argon2id" || parts[2] != "v=19" {
		return argon2Parameters{}, nil, nil, malformedPasswordHash("invalid PHC structure")
	}

	params, err := parseArgon2Parameters(parts[3])
	if err != nil {
		return argon2Parameters{}, nil, nil, err
	}

	if len(parts[4]) < base64.RawStdEncoding.EncodedLen(defaultSaltBytes) ||
		len(parts[4]) > base64.RawStdEncoding.EncodedLen(maxSaltBytes) {
		return argon2Parameters{}, nil, nil, malformedPasswordHash("invalid salt length")
	}
	if len(parts[5]) != base64.RawStdEncoding.EncodedLen(int(passwordKeyBytes)) {
		return argon2Parameters{}, nil, nil, malformedPasswordHash("invalid key length")
	}

	salt, err := base64.RawStdEncoding.Strict().DecodeString(parts[4])
	if err != nil || len(salt) < defaultSaltBytes || len(salt) > maxSaltBytes {
		return argon2Parameters{}, nil, nil, malformedPasswordHash("invalid salt encoding")
	}
	expectedKey, err := base64.RawStdEncoding.Strict().DecodeString(parts[5])
	if err != nil || len(expectedKey) != int(passwordKeyBytes) {
		return argon2Parameters{}, nil, nil, malformedPasswordHash("invalid key encoding")
	}

	return params, salt, expectedKey, nil
}

func parseArgon2Parameters(encoded string) (argon2Parameters, error) {
	fields := strings.Split(encoded, ",")
	if len(fields) != 3 {
		return argon2Parameters{}, malformedPasswordHash("invalid parameters")
	}

	memory, ok := parseUintParameter(fields[0], "m=", 32)
	if !ok || memory < uint64(defaultMemoryKiB) || memory > uint64(maxMemoryKiB) {
		return argon2Parameters{}, malformedPasswordHash("unsafe memory cost")
	}
	timeCost, ok := parseUintParameter(fields[1], "t=", 32)
	if !ok || timeCost < uint64(defaultTime) || timeCost > uint64(maxTime) {
		return argon2Parameters{}, malformedPasswordHash("unsafe time cost")
	}
	threads, ok := parseUintParameter(fields[2], "p=", 8)
	if !ok || threads < uint64(defaultThreads) || threads > uint64(maxThreads) {
		return argon2Parameters{}, malformedPasswordHash("unsafe parallelism")
	}

	return argon2Parameters{memoryKiB: uint32(memory), time: uint32(timeCost), threads: uint8(threads)}, nil
}

func parseUintParameter(encoded, prefix string, bitSize int) (uint64, bool) {
	if !strings.HasPrefix(encoded, prefix) || len(encoded) == len(prefix) {
		return 0, false
	}
	digits := encoded[len(prefix):]
	if len(digits) > 1 && digits[0] == '0' {
		return 0, false
	}
	value, err := strconv.ParseUint(digits, 10, bitSize)
	return value, err == nil
}

func malformedPasswordHash(reason string) error {
	return fmt.Errorf("%w: %s", ErrMalformedPasswordHash, reason)
}
