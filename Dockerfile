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
