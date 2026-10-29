# Static-site / SPA via Nginx

> **Not yet proven on a GroupBees project.** A starting point, not a
> convention: validate it on the first real project, then remove this note.

```dockerfile
# ---- builder (Vite, Next.js export, etc.) ----
FROM node:22-bookworm-slim AS builder
…
RUN pnpm build   # outputs to ./dist

# ---- runtime: official non-root nginx ----
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=nginx:nginx /usr/local/src/app/dist /usr/share/nginx/html
EXPOSE 8080   # nginx-unprivileged listens on 8080, not 80
# USER nginx + default ENTRYPOINT/CMD inherited from the base image.
```

The corresponding `nginx.conf` must `listen 8080;` (not 80) — UID 101
can't bind privileged ports.
