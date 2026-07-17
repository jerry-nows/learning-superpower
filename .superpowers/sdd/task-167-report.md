# CR-167 implementation report

## Status

Complete.

## Changes

- Added authenticated `GET /v1/products/{id}/reviews` handler.
- Added authenticated `GET /v1/products/{id}/comments` handler.
- Added authenticated `GET /v1/products/{id}/stock` handler.
- Added exact product-detail path validation shared by detail and section handlers.
- Preserved section isolation: repository errors are translated only for the requested section.
- Added success, unavailable-section, invalid-path, and method contract tests.

## Verification

```text
go test ./internal/product   PASS
go test ./...                PASS
```

## Notes

The router wiring is intentionally left to CR-168. The iOS client currently names the stock section `inventory`; a route alias can be added during API wiring if required by the client contract.

## Review follow-up

- Added `/inventory` as an API-compatible alias for `/stock`.
- Added `/rating-summary`, deriving average rating and review count from the independent reviews read.
- Added unauthorized coverage for every detail section endpoint.

```text
go test ./...                PASS
```
