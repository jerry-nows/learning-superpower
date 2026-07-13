# CR-044 family ID fix

Family IDs are now generated independently using a 128-bit CSPRNG value and
canonical base64url encoding. They are no longer derived from refresh-token
digests. Generation is injectable for deterministic tests and failures map to
the safe token-issue error.

Validation: `go test ./...`, `gofmt` pass.
