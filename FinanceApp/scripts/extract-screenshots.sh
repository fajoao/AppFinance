#!/usr/bin/env bash
# Extrai os anexos (capturas de tela) de um .xcresult gerado pelos testes de UI para uma pasta.
# Uso: FinanceApp/scripts/extract-screenshots.sh <caminho.xcresult> [pasta-destino]
# O padrão do destino é Docs/screenshots/ na raiz do repositório. Requer Xcode (xcrun xcresulttool).
set -euo pipefail
RESULT="${1:?uso: extract-screenshots.sh <caminho.xcresult> [pasta-destino]}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="${2:-$ROOT/Docs/screenshots}"
mkdir -p "$DEST"
# Xcode 16+: `xcresulttool export attachments`. Gera um manifest.json com os nomes dos testes e arquivos.
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$DEST"
echo "Capturas extraídas em: $DEST"
