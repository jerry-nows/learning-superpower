# Phase 3 Authentication — CR-043

## API

- `NewRefreshToken(io.Reader)` generates an opaque token; a nil reader uses `crypto/rand.Reader`.
- `ParseRefreshToken(string)` accepts only unpadded, canonical base64url encoding of exactly 32 decoded bytes.
- `RefreshToken.Encoded()` is the explicit transport accessor; `RefreshToken.Digest()` is the explicit storage accessor.
- `EqualRefreshTokenDigest` performs constant-time comparison of fixed-size SHA-256 digests.

## Security

The raw 256-bit value is held in an unexported field and is never a JSON field. Redis-facing storage uses SHA-256 over the exact presented encoded value, not over decoded bytes. No JWT representation or persistence was added. Whitespace, padding, malformed base64, empty values, and wrong decoded lengths are rejected. Short injected random sources fail closed.

## TDD

RED was confirmed first: focused tests failed to compile because the refresh-token API did not exist. GREEN was reached with the minimal implementation, followed by `gofmt`, `go test -race ./internal/auth`, `go vet ./internal/auth`, and `git diff --check`.

## Hash

The storage digest is `sha256.Sum256([]byte(encodedTransportValue))`; the fixed 32-byte digest is returned by value to prevent mutation.
