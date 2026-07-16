# CR-143 review fixes

- Added migration-directory validation before any database or Redis opener executes.
- Extended the startup seam with an injectable SQL close hook and verified cleanup when startup fails.
- Added focused tests for fail-fast migration configuration and resource cleanup.

Verification: `go test ./...`, `go test -race ./cmd/api ./internal/...`, `go vet ./...`, and `gofmt` pass.
