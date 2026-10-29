---
name: docker-image-conventions
description: Stack-agnostic conventions for writing production-grade Dockerfiles — multi-stage builds (builder + lean runtime), non-root user at runtime, smallest viable base image (alpine when possible, slim/debian when glibc-linked libs force it), split `ENTRYPOINT` / `CMD`, layered caching, `WORKDIR=/usr/local/src/app`. Includes per-language cheatsheets (Node, Go, Rust, JVM, Nginx) and a decision rubric for alpine vs slim. Trigger when creating, editing, or reviewing any Dockerfile, picking a runtime base image, dropping root in an existing image, or discussing image-size / hardening. For Python+uv specifically, see `python-docker-multistage` (it composes on top of this skill).
---

# Production Docker images — multi-stage + non-root

Five rules apply to every language:

1. **Multi-stage build.** A `builder` stage with toolchain (compilers,
   package manager, transpiler) and a `runtime` stage with only the
   built artifact + its runtime deps. Drops 80–95 % of image size.
2. **Non-root user at runtime.** PID 1 must not be `root`. Create a
   system user/group in the runtime stage (or use a base image that
   already does this, e.g. `nginxinc/nginx-unprivileged`, official
   `node` images with the `node` user).
3. **Smallest viable base image.** Default to alpine; fall back to
   `-slim` (debian) when glibc-linked binaries don't run on musl.
4. **`ENTRYPOINT` (executable) + `CMD` (default args), split.** Lets
   callers override args without re-quoting the whole command.
5. **`WORKDIR=/usr/local/src/app`**, parameterised through `ARG APP_DIR`
   / `ENV APP_DIR` so the path is named once. Linux-FHS aligned, not
   `/app`.

## Universal reference shape

```dockerfile
# syntax=docker/dockerfile:1.7

ARG APP_DIR=/usr/local/src/app

# ---------- builder ----------
FROM <toolchain-image> AS builder
ARG APP_DIR
ENV APP_DIR=${APP_DIR}
WORKDIR ${APP_DIR}

# Install dependencies first (best cache layer), then copy source.
COPY <dep-manifests> ./
RUN <install-deps>
COPY <source> ./
RUN <build>

# ---------- runtime ----------
FROM <lean-runtime-image> AS runtime
ARG APP_DIR=/usr/local/src/app
ENV APP_DIR=${APP_DIR}
WORKDIR ${APP_DIR}

# Create the unprivileged user BEFORE the COPY so --chown works.
RUN groupadd --system app \
 && useradd --system --gid app --home-dir ${APP_DIR} --shell /usr/sbin/nologin app \
 && chown app:app ${APP_DIR}

COPY --from=builder --chown=app:app ${APP_DIR}/<artifact> ${APP_DIR}/<artifact>

USER app
EXPOSE <port>

ENTRYPOINT ["<binary>"]
CMD ["<default-arg>", "..."]
```

On alpine, `groupadd`/`useradd` aren't installed — use `addgroup -S` /
`adduser -S -G` instead:

```dockerfile
RUN addgroup -S app && adduser -S -G app -h ${APP_DIR} -s /sbin/nologin app
```

## Base image: alpine vs slim — decision rubric

**Default to alpine.** Switch to `-slim` (debian-bookworm or
debian-trixie) when one of:

- Native code linked against **glibc** (most pre-built wheels in PyTorch /
  NumPy / SciPy / Pandas; ICU-using JVM apps; many CLI tools shipped as
  prebuilt binaries; `psycopg2-binary`; `grpc` pre-built; `node-canvas`,
  `sharp`, `bcrypt` prebuilds).
- Vendor SDK or proprietary binary you can't recompile (Oracle client,
  some Google Cloud / AWS native helpers, closed-source DRM libs).
- Heavy `libstdc++` / `libgomp` usage that the base musl runtime lacks.
- You hit DNS-resolution oddities (musl's resolver is stricter; some
  legacy apps misbehave).

If you can't tell, build both and see which one works first; the size
delta (often ~50–100 MB on slim vs ~5–30 MB on alpine) is usually
worth a quick experiment.

## Non-root user — patterns per base

| Base | Pattern |
|---|---|
| `*-slim` / debian | `groupadd --system app && useradd --system --gid app …`, then `USER app`. |
| `*-alpine` | `addgroup -S app && adduser -S -G app …`, then `USER app`. |
| `nginx:*` | **Don't.** Switch the image to `nginxinc/nginx-unprivileged:*` — it ships UID 101 + listens on 8080, ready-made. |
| `node:*` | A `node` user (UID 1000) already exists. `USER node` is enough. |
| `eclipse-temurin:*-jre` | No app user pre-created. Add one as for debian/alpine, then `USER app`. |
| `gcr.io/distroless/*` | The `nonroot` variants already run as UID 65532. Use them by tag (`:nonroot`). |

**Port binding:** non-root processes can't bind ports <1024 without
`CAP_NET_BIND_SERVICE`. Default to 8080 for HTTP, 8443 for HTTPS — the
host-side `-p` mapping can still be `80:8080` if you really want the
external port to be 80.

## Layer caching — deps before source

The single biggest cache win is copying dependency manifests first,
running the install command (cached as long as the manifests don't
change), then copying the rest. Applies to every language:

| Language | Dep manifests | Install command |
|---|---|---|
| Python (uv) | `pyproject.toml`, `uv.lock` | `uv sync --frozen --no-install-project --no-dev` |
| Node (pnpm) | `package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml` (pnpm-10+) | `pnpm install --frozen-lockfile` |
| Go | `go.mod`, `go.sum` | `go mod download` |
| Rust | `Cargo.toml`, `Cargo.lock` | `cargo fetch` (or the cargo-chef pattern) |
| JVM (Maven) | `pom.xml`, `mvnw`, `.mvn/` | `./mvnw -B dependency:go-offline` |
| JVM (Gradle) | `build.gradle.kts`, `settings.gradle.kts`, `gradle/`, wrapper | `./gradlew --no-daemon dependencies` |

## Per-language cheatsheets

The five rules above apply as is. For the reference Dockerfile of a stack,
read **only** the matching file:

| Stack | Reference | Base images |
|-------|-----------|-------------|
| Node (SSR / API server) | [`references/node.md`](references/node.md) | `node:*-bookworm-slim` → `node:*-alpine` |
| Static site / SPA — *not yet proven* | [`references/nginx.md`](references/nginx.md) | `nginxinc/nginx-unprivileged` (listens on 8080) |
| Go (static binary) — *not yet proven* | [`references/go.md`](references/go.md) | `golang:*-alpine` → `distroless/static:nonroot` |
| Rust (release binary) — *not yet proven* | [`references/rust.md`](references/rust.md) | `rust:*-alpine` (musl) → `alpine` |
| JVM (Java / Kotlin, Maven) — *not yet proven* | [`references/jvm.md`](references/jvm.md) | `temurin:*-jdk-alpine` → `temurin:*-jre-alpine` |
| Python + uv | the `python-docker-multistage` skill | — |

## Don't

- Don't `USER root` then forget to switch back. Last `USER` in the file
  is what PID 1 inherits.
- Don't `chmod 777`. Use `--chown=user:group` at COPY time.
- Don't `apt-get install -y curl` "just to test" — every byte costs.
  Use `wget`/`curl` only in the builder stage if needed for a download,
  not in runtime.
- Don't run the build as root in the runtime stage — separate the user
  creation from the install commands.
- Don't pin to `:latest`. Pin a specific minor version (`1.27-alpine`,
  `21-jre-alpine`).
- Don't bake secrets into image layers. Use `--mount=type=secret` (BuildKit)
  or runtime env injection.
