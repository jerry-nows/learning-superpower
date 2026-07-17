# CR-144 review fix report

- Aligned OpenAPI responses with `Backend/internal/auth/handler.go` and router behavior: 400, 401, 405, 408 and 500; removed unsupported 503.
- Added exact emitted `AUTH_*` code enum, including logout bearer `AUTH_UNAUTHORIZED`, and optional `field_violations` entries.
- Strengthened contract tests for POST-only operations, required status coverage, logout security, unsupported 503 rejection, duplicate YAML keys and component `$ref` resolution.

Verification: `go test ./api ./internal/auth ./internal/platform/httpapi` passes after RED/GREEN review changes.
