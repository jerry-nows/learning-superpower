# CR-046 final fix report

- Content-Type now accepts only bare `application/json` or one `charset=utf-8` parameter; unknown, empty, and additional parameters are rejected.
- Cancellation error codes always force HTTP 408 and `retryable=false`, even if a service error incorrectly marks them retryable.
- Regression tests cover all parameter variants and cancellation metadata.

Validation passed: focused tests, race, vet, full `go test ./...`, gofmt, and diff check.
