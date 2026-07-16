# CR-144 implementation report

- Added `Backend/api/openapi.yaml` (OpenAPI 3.1.0) for login, refresh and bearer logout.
- Contract models match the handler DTOs: nested `user` and `tokens`, token expiry fields, and 204 logout.
- Documented exact 60-second access JWT lifetime, opaque 256-bit refresh token and digest-only storage.
- Added stable error envelope and malformed/unauthorized/timeout/unavailable HTTP responses.
- Added a Go contract test that validates required paths/schemas, rejects duplicate YAML mapping keys and scans examples for secrets.

## Verification

- RED: `go test ./api` failed before the manifest existed.
- GREEN: `go test ./api ./internal/auth ./internal/platform/httpapi` passed.
- `git diff --check` reports only pre-existing whitespace in unrelated reports.
- Python YAML parser was unavailable in the environment; the Go YAML parser contract test is the validation authority.
