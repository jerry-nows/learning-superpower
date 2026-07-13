# CR-141 review-fix report

Expanded seed command coverage with table-driven validation and operation-failure contracts. Tests now prove successful ping followed by hashing failure never executes SQL, each required environment variable is independently rejected when missing/invalid, and open/exec failures remain generic and redacted.

Added a PostgreSQL 16 Alpine testcontainers integration test. It applies the auth migration, runs the seed command twice with a production Argon2id hasher and test-only environment credentials, and verifies exactly one normalized active user with a non-empty hash. The test explicitly skips when the Docker provider is unhealthy.

Verification: `go test ./...`, `go test -race ./cmd/seed`, `go vet ./cmd/seed`, and `gofmt` pass.

Final review fix also asserts returned errors (not only captured output) remain free of DSNs, email, password, and hashes across ping, hash, open, and Exec failure branches.
