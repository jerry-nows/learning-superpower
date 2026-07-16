# CR-142 final fix

Aligned the nil authentication boundary branch with the OpenAPI contract. A composition-time missing auth handler now returns HTTP 500 with the stable JSON code `AUTH_INTERNAL`, instead of exposing a 503 availability response.

Added the contract assertion and verified with `go test -race ./internal/platform/httpapi`, `go test ./...`, and `go vet ./...`. The only `git diff --check` warning remains pre-existing whitespace in `phase3-cr140-report.md`.
