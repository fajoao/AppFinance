#!/usr/bin/env bash
# Compila Core + App/Logic + App/Store + AppTests com swiftc (sem Xcode/SwiftPM) e executa os testes de lógica do app.
# Nenhum desses arquivos importa SwiftUI. Os testes de UI (UITests) só rodam no Xcode.
# Uso: FinanceApp/scripts/test-app.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/financeapp-tests.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
LANG_MODE="${SWIFT_LANGUAGE_MODE:-6}"

shopt -s nullglob
SOURCES=("$ROOT"/Core/*.swift "$ROOT"/App/Logic/*.swift "$ROOT"/App/Store/*.swift "$ROOT"/AppTests/Cases/*.swift "$ROOT"/AppTests/Runner/main.swift)
if grep -l "import SwiftUI" "$ROOT"/App/Logic/*.swift "$ROOT"/App/Store/*.swift 2>/dev/null; then
  echo "ERRO: App/Logic e App/Store não podem importar SwiftUI (precisam compilar sem Xcode)." >&2; exit 2
fi
echo "==> Compilando ${#SOURCES[@]} arquivos (Swift language mode $LANG_MODE)"
swiftc -swift-version "$LANG_MODE" -O -warnings-as-errors -o "$OUT/app-tests" "${SOURCES[@]}"
echo "==> Executando"
"$OUT/app-tests"
