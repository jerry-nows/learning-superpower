# CR-139 review fix report

Addressed review findings:

- Create now uses one atomic Lua transaction for session hash, TTL and family/user indexes.
- Session and index keys retain bounded 24-hour replay tombstones after expiry, allowing expired-token replay detection and family revocation while remaining self-cleaning.
- Rotation computes `now` once and uses ceil-style positive millisecond TTL handling.
- Replacement digests equal to the presented digest are rejected before Redis evaluation.

Validation: `go test ./...` and `go vet ./...` pass in `Backend`.
