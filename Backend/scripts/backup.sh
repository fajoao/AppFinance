#!/usr/bin/env bash
# Backup do Postgres (pg_dump, formato custom comprimido) para ./backups/. Uso: Backend/scripts/backup.sh [diretório]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
OUT_DIR="${1:-$ROOT/backups}"
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"
FILE="$OUT_DIR/finance-$(date +%Y%m%d-%H%M%S).dump"
umask 077
# Usuário/banco vêm do próprio container (variáveis de ambiente do serviço db); a senha não passa pela linha de comando.
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --compress=9 --no-owner' > "$FILE"
[ -s "$FILE" ] || { rm -f "$FILE"; echo "backup vazio, abortado" >&2; exit 1; }
echo "Backup criado: $FILE ($(wc -c < "$FILE" | tr -d ' ') bytes)"
echo "Guarde cópias fora desta máquina e criptografadas (o dump contém dados financeiros)."
