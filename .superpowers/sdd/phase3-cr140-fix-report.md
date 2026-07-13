# CR-140 follow-up report

Strengthened the Redis integration suite after review:

- After family reuse revocation, rotation attempts using both the issued
  replacement and a sibling session are rejected, with no replacement key
  resurrected.
- Replaced broad `KEYS` inspection with Redis `SCAN auth:refresh:*`.
- SCAN assertions prove raw opaque token values never occur in key names and
  the SHA-256 digest does occur.

Verification: focused integration test, focused `-race`, `go test ./...`,
`go vet ./...`, gofmt, and test-file diff checks all passed. Docker-unhealthy
environments continue to skip explicitly through testcontainers.
