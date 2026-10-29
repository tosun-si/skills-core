# Go (static binary)

> **Not yet proven on a GroupBees project.** A starting point, not a
> convention: validate it on the first real project, then remove this note.

```dockerfile
# ---- builder ----
FROM golang:1.23-alpine AS builder
WORKDIR /usr/local/src/app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/app ./cmd/server

# ---- runtime: scratch or distroless ----
FROM gcr.io/distroless/static-debian12:nonroot AS runtime
WORKDIR /
COPY --from=builder --chown=nonroot:nonroot /out/app /app
USER nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]
```

Distroless `:nonroot` runs as UID 65532 and ships nothing but the
binary + CA certs + tzdata. Use `scratch` only if you don't need TLS
or timezone data.
