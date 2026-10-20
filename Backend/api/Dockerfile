# Contexto de build: ./Backend  (docker compose: build.context=Backend, dockerfile=api/Dockerfile)
FROM node:22-bookworm-slim AS deps
WORKDIR /app
COPY api/package.json api/package-lock.json ./
RUN npm ci

FROM deps AS build
COPY api/tsconfig.json api/tsconfig.build.json ./
COPY api/src ./src
RUN npx tsc -p tsconfig.build.json

# Imagem de testes (docker compose --profile test run --rm api-test): inclui devDependencies e as migrações.
FROM build AS test
COPY api/vitest.config.ts ./
COPY api/test ./test
COPY db/migrations /app/db/migrations
ENV MIGRATIONS_DIR=/app/db/migrations
CMD ["npx", "vitest", "run"]

FROM node:22-bookworm-slim AS prod-deps
WORKDIR /app
COPY api/package.json api/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=prod-deps --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist
COPY --chown=node:node api/package.json ./
COPY --chown=node:node db/migrations /app/db/migrations
USER node
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/server.js"]
