#!/usr/bin/env bash
# Restaura um dump gerado por backup.sh. DESTRUTIVO: substitui os dados do banco atual.
# Uso: Backend/scripts/restore.sh backups/finance-XXXX.dump   (peça confirmação digitando "restaurar")
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
FILE="${1:?uso: restore.sh <arquivo.dump>}"
[ -f "$FILE" ] || { echo "arquivo não encontrado: $FILE" >&2; exit 1; }
if [ "${FORCE:-}" != "1" ]; then
  read -r -p "Isto APAGA e substitui os dados atuais. Digite 'restaurar' para continuar: " ans
  [ "$ans" = "restaurar" ] || { echo "cancelado"; exit 1; }
fi
docker compose stop api >/dev/null 2>&1 || true   # evita gravações durante a restauração
docker compose exec -T db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --single-transaction' < "$FILE"
docker compose start api >/dev/null 2>&1 || true
echo "Restauração concluída a partir de $FILE"
