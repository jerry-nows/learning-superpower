# CR-144 final review fix

- Expanded contract secret scanning to reject PEM private keys, JWT-like three-segment values, DSN schemes, long secret assignments and non-redacted auth field examples while allowing explicit placeholders.
- Asserted exact response status sets: login/refresh `200,400,401,405,408,500`; logout `204,401,405,408,500`.
- Existing `$ref`, duplicate-key and bearer-security checks remain active.

Verification: `go test ./...` passes. `git diff --check` only reports pre-existing whitespace in an unrelated report.
