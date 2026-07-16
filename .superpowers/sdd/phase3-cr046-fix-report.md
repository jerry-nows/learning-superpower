# CR-046 review-fix report

- Parsed media types with `mime.ParseMediaType`; only `application/json` and optional UTF-8 charset are accepted.
- Method failures now return JSON `AUTH_METHOD_NOT_ALLOWED`, `Allow`, trace ID, and non-retryable metadata.
- Cancellation/token-issue cancellation maps to HTTP 408 and never exposes wrapped causes.
- Added tests for refresh errors, strict content types, trailing/oversized bodies, method envelopes, retryability, and cancellation secrecy.

Validation passed: `go test ./...`, `go test -race ./internal/auth`, `go vet ./internal/auth`, `gofmt`, `git diff --check`.
