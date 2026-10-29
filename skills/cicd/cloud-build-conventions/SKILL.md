---
name: cloud-build-conventions
description: Conventions for writing Google Cloud Build configurations (cloudbuild.yaml). Trigger when creating, editing, or reviewing cloudbuild.yaml, or when discussing how to build Docker images in GCP CI/CD pipelines with Buildx + registry cache.
---

# Cloud Build conventions

- **Prefer multi-line `script` blocks** over `args` with multiple dashes — more readable, supports bash idioms cleanly.
- **Builder image**: use `gcr.io/google.com/cloudsdktool/google-cloud-cli:stable` instead of `gcr.io/cloud-builders/gcloud` (smaller image, same gcloud).
- **Docker builds**: use **Buildx with registry cache** for fast, deterministic incremental builds.
- **Combine build + push** in a single Buildx step (`--push` flag) — no separate push step needed.
- **Cache image tag convention**: `<image>:buildcache` in the same Artifact Registry repo.

## Reference shape — build + push with Buildx + registry cache

```yaml
steps:
  - name: 'gcr.io/cloud-builders/docker'
    script: |
      docker buildx create --use
      docker buildx build \
        -t $${IMAGE_PATH} \
        --push \
        --cache-from=type=registry,ref=$${CACHE_IMAGE} \
        --cache-to=type=registry,ref=$${CACHE_IMAGE},mode=max .

substitutions:
  _IMAGE_PATH: europe-west1-docker.pkg.dev/$PROJECT_ID/app/api:$SHORT_SHA
  _CACHE_IMAGE: europe-west1-docker.pkg.dev/$PROJECT_ID/app/api:buildcache

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: E2_HIGHCPU_8
```

## When NOT to use Buildx

- Trivial single-stage builds with no layer-cache benefit (rare in production).
- When the team uses Cloud Build's native Kaniko cache as a standard (different cache model — pick one and stick with it).
