# syntax=docker/dockerfile:1

# --- Stage 1: install dependencies -----------------------------------------
# Uses the full node:20-alpine image (has npm) only to resolve/install deps.
# Kept separate from the runtime stage so build tooling never ends up in the
# final image.
FROM node:20-alpine AS deps
WORKDIR /app
COPY app/package.json app/package-lock.json ./
# npm ci with --omit=dev: deterministic install from the lockfile, no dev
# dependencies (there are none today, but this keeps the image minimal if
# dev-only tooling is added later, e.g. a linter or test framework).
RUN npm ci --omit=dev

# --- Stage 2: runtime --------------------------------------------------------
FROM node:20-alpine AS runtime
ENV NODE_ENV=production \
    PORT=8080

WORKDIR /app

# Alpine already ships a low-privilege "node" user/group (uid/gid 1000) in
# the official node image, so we reuse it instead of creating a new one.
COPY --from=deps /app/node_modules ./node_modules
COPY app/package.json ./
COPY app/server.js ./

# Drop root before the app ever runs.
USER node

EXPOSE 8080

# Container-level liveness check, hitting the same /health endpoint that
# Kubernetes/Container Apps probes and the CI smoke test use. wget is
# available in alpine's busybox and avoids adding curl to the image.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1

CMD ["node", "server.js"]
