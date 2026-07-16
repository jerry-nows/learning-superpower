# CR-142 health method boundary fix

Added router-level method enforcement for `/healthz`.

- Only `GET` reaches the supplied health handler.
- `POST` and `PUT` return the stable JSON method error with `Allow: GET`.
- Regression coverage added for both wrong methods.

Verification: `go test -race ./internal/platform/httpapi`, `go test ./...`, and `go vet ./...` pass. `git diff --check` reports only the pre-existing trailing whitespace in `phase3-cr140-report.md`.
