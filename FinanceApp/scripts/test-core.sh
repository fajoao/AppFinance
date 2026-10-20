#!/usr/bin/env bash
# Compila Core/*.swift + CoreTests/*.swift com swiftc (sem Xcode/SwiftPM) e executa os testes.
# Uso: FinanceApp/scripts/test-core.sh   (código de saída != 0 se algum teste falhar)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/financecore.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
SWIFT_VERSION_FLAG="${SWIFT_LANGUAGE_MODE:-6}"

shopt -s nullglob
SOURCES=("$ROOT"/Core/*.swift "$ROOT"/CoreTests/*.swift)
echo "==> Compilando ${#SOURCES[@]} arquivos (Swift language mode $SWIFT_VERSION_FLAG)"
swiftc -swift-version "$SWIFT_VERSION_FLAG" -O -warnings-as-errors -o "$OUT/core-tests" "${SOURCES[@]}"
echo "==> Executando"
"$OUT/core-tests"
