# syntax=docker/dockerfile:1

# Stage 1: install deps only, so build tooling never reaches the final image.
FROM node:20-alpine AS deps
WORKDIR /app
COPY app/package.json app/package-lock.json ./
RUN npm ci --omit=dev

# Stage 2: runtime
FROM node:20-alpine AS runtime
ENV NODE_ENV=production \
    PORT=8080

WORKDIR /app

# Patches OS packages (e.g. openssl) against CVEs fixed after this image was published.
RUN apk upgrade --no-cache

# npm/npx/corepack/yarn ship in the base image for build-time use only; the
# app only needs `node` to run, so drop them to shrink the attack surface.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
    /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
    /usr/local/bin/yarn /usr/local/bin/yarnpkg /opt/yarn-v*

# Reuses the low-privilege "node" user/group the base image already ships.
COPY --from=deps /app/node_modules ./node_modules
COPY app/package.json ./
COPY app/server.js ./

USER node

EXPOSE 8080

# wget comes from alpine's busybox, avoiding an extra curl install.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1

CMD ["node", "server.js"]
