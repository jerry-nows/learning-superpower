# CR-139 final fix report

Resolved the remaining lifecycle findings. RevokeUser and rotation family revocation now refresh bounded tombstone TTLs and only mutate existing session keys. Create atomically returns a collision code for duplicate digest keys; Rotate detects replacement collisions before consuming the presented token and maps the result safely. Contract regression checks cover collision and TTL script markers.

Validation completed: `go test ./...`, `go test -race ./internal/auth`, and `go vet ./...` all pass.
