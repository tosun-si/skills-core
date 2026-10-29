# Rust (release binary)

> **Not yet proven on a GroupBees project.** A starting point, not a
> convention: validate it on the first real project, then remove this note.

```dockerfile
# ---- builder (musl target → fully static binary) ----
FROM rust:1.83-alpine AS builder
RUN apk add --no-cache musl-dev
WORKDIR /usr/local/src/app
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release && rm -rf src target/release/deps/myapp*
COPY . .
RUN cargo build --release

# ---- runtime ----
FROM alpine:3.20 AS runtime
RUN addgroup -S app && adduser -S -G app app
COPY --from=builder --chown=app:app /usr/local/src/app/target/release/myapp /usr/local/bin/myapp
USER app
EXPOSE 8080
ENTRYPOINT ["myapp"]
```

For glibc-dependent crates, switch builder to `rust:1.83-bookworm-slim`
and runtime to `gcr.io/distroless/cc-debian12:nonroot`.
