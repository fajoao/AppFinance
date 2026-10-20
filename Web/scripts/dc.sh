#!/usr/bin/env bash
# Roda um comando do Node 22 dentro do Docker (a máquina não tem npm).
# node_modules fica em um volume nomeado (rápido e não polui a pasta).
# Uso: Web/scripts/dc.sh npm test
set -euo pipefail
WEB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec docker run --rm -v "$WEB":/app -v financeweb_node_modules:/app/node_modules -w /app \
  -e API_URL="${API_URL:-}" node:22 "$@"
