#!/usr/bin/env bash
# Roda o E2E (Playwright em container) contra o stack em http://localhost:8080 (docker compose up -d --build).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HERE/../../docs/web-screenshots"
docker run --rm --add-host=host.docker.internal:host-gateway \
  -v "$HERE":/src:ro -v "$HERE/../../docs/web-screenshots":/shots \
  -e BASE_URL="${BASE_URL:-http://host.docker.internal:8080}" -w /work mcr.microsoft.com/playwright:v1.49.1-jammy \
  sh -c 'cp /src/e2e.mjs . && npm init -y >/dev/null && npm i playwright@1.49.1 --silent >/dev/null 2>&1 && node e2e.mjs'
