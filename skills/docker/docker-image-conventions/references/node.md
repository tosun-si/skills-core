# Node (SSR / API server)

```dockerfile
# ---- builder ----
FROM node:22-bookworm-slim AS builder
ENV PNPM_HOME=/pnpm PATH=/pnpm:$PATH
RUN corepack enable
WORKDIR /usr/local/src/app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# ---- runtime ----
FROM node:22-alpine AS runtime
WORKDIR /usr/local/src/app
COPY --from=builder --chown=node:node /usr/local/src/app/dist ./dist
COPY --from=builder --chown=node:node /usr/local/src/app/node_modules ./node_modules
COPY --from=builder --chown=node:node /usr/local/src/app/package.json ./
USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

`node:*-alpine` is fine 90 % of the time. If you use `sharp`, `canvas`,
`grpc`, or `bcrypt` (prebuilds), switch the runtime to `node:22-bookworm-slim`.
