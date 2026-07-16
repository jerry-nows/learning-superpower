# CR-043 Security Fix

The `RefreshToken.String()` implementation was removed because implicit string
formatting exposed the bearer value. A focused regression test first failed
(RED) against that implementation, then passed (GREEN) after removal and an
explicit `fmt.Formatter` redaction boundary was added. `%v` and `%s` now emit a
redacted marker; callers must invoke `Encoded()` deliberately for transport.

Verification: `go test ./internal/auth -run RefreshToken`,
`go test -race ./internal/auth`, `go vet ./internal/auth`, `gofmt`, and
`git diff --check` all pass.
