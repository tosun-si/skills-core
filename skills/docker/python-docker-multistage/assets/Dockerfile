# syntax=docker/dockerfile:1.7
#
# Python + uv, multi-stage, non-root. Copy to the project root, replace
# <package> with the import package (e.g. quote_service), adjust the CMD.

ARG APP_DIR=/usr/local/src/app

# ---------- builder ----------
FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim AS builder
ARG APP_DIR
ENV APP_DIR=${APP_DIR}
WORKDIR ${APP_DIR}

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

# Deps first — cached as long as pyproject.toml + uv.lock don't change.
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --no-dev

# Then the project itself.
COPY <package> ./<package>
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# ---------- runtime (no uv) ----------
FROM python:3.13-slim-bookworm AS runtime
ARG APP_DIR=/usr/local/src/app
ENV APP_DIR=${APP_DIR} \
    PATH="${APP_DIR}/.venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR ${APP_DIR}

RUN groupadd --system app \
 && useradd --system --gid app --home-dir ${APP_DIR} --shell /usr/sbin/nologin app \
 && chown app:app ${APP_DIR}

COPY --from=builder --chown=app:app ${APP_DIR}/.venv ${APP_DIR}/.venv
COPY --from=builder --chown=app:app ${APP_DIR}/<package> ${APP_DIR}/<package>

USER app
# Cloud Run default port, the one cloud-run-cicd-gha deploys with (--port=8080).
EXPOSE 8080

ENTRYPOINT ["uvicorn"]
CMD ["<package>.main:app", "--host", "0.0.0.0", "--port", "8080"]
