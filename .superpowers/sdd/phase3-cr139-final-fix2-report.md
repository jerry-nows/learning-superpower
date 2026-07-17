# CR-139 final fix 2 report

Successful rotation now refreshes the authoritative user-family index TTL to the replacement lifetime plus the bounded replay grace. This keeps active families discoverable by `RevokeUser` after rotation while preserving automatic cleanup.

Validation: `go test ./...`, `go test -race ./internal/auth`, and `go vet ./...` pass.
