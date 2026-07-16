FROM golang:1.26.5-alpine AS build

WORKDIR /src
COPY go.mod ./
COPY go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
COPY migrations ./migrations
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/seed ./cmd/seed

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/api /api
COPY --from=build /out/seed /seed
COPY --from=build /src/migrations /migrations
EXPOSE 8080
USER 10001:10001
ENTRYPOINT ["/api"]
